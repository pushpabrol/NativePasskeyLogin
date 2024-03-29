/*
 AccountStore manages account sign in and out.
 */

#if os(iOS) || os(macOS)

import AuthenticationServices
import SwiftUI
import Combine
import os
import Alamofire

public enum AuthorizationHandlingError: Error {
    // Enumeration for different authorization handling errors
    case unknownAuthorizationResult(ASAuthorizationResult)
    case otherError
    case duplicateError
}

extension AuthorizationHandlingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownAuthorizationResult:
            return NSLocalizedString("Received an unknown authorization result.", comment: "Human readable description of receiving an unknown authorization result.")
        case .otherError:
            return NSLocalizedString("Encountered an error handling the authorization result.", comment: "Human readable description of an unknown error while handling the authorization result.")
        case .duplicateError:
            return NSLocalizedString("Encountered an error handling the registration.", comment: "A user with the same username already exists!")
        }
    }
}

@MainActor
public final class AccountStore: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    // AccountStore class manages account sign in and out
    
    @Published public private(set) var currentUser: User? = .none
    public var authzError: Bool = false
    public private(set) var authzErrorMessage: String? = nil
    
    public var isSignedIn: Bool {
        // Returns true if the currentUser is not nil
        currentUser != nil || currentUser != .none
    }
    
    /**
     Performs sign-in with a passkey account.
     
     - Parameters:
        - authorizationController: The AuthorizationController instance.
        - options: Additional options for the authorization request.
     */
    public func signIntoPasskeyAccount(authorizationController: AuthorizationController, options: ASAuthorizationController.RequestOptions = []) async {
        // Attempts to perform sign-in requests using authorizationController
        do {
            let authorizationResult = try await authorizationController.performRequests(signInRequests(), options: options)
            try await handleAuthorizationResult(authorizationResult)
        } catch let authorizationError as ASAuthorizationError where authorizationError.code == .canceled {
            // Handles user cancellation during authorization
            print("The user cancelled passkey authorization.")
            self.authzError = true
            self.authzErrorMessage = "The user cancelled passkey authorization."
        } catch let authorizationError as ASAuthorizationError {
            // Handles other authorization errors
            print("Passkey authorization failed. Error: \(authorizationError.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey authorization failed. Error: \(authorizationError.localizedDescription)"
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Handles unknown authorization results
            print("Passkey authorization handling failed. Received an unknown result: \(String(describing: authorizationResult))")
            self.authzError = true
            self.authzErrorMessage = "Passkey authorization handling failed. Received an unknown result: \(String(describing: authorizationResult))"
        } catch {
            // Handles unknown errors during authorization
            print("Passkey authorization handling failed. Caught an unknown error during passkey authorization or handling: \(error.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey authorization handling failed. Caught an unknown error during passkey authorization or handling: \(error.localizedDescription)"
        }
    }
    
    /**
     Performs passkey account creation.
     
     - Parameters:
        - authorizationController: The AuthorizationController instance.
        - username: The username for registration.
        - options: Additional options for the authorization request.
     */
    public func createPasskeyAccount(authorizationController: AuthorizationController, username: String, options: ASAuthorizationController.RequestOptions = []) async {
        // Attempts to perform registration request using authorizationController
        do {
            let authorizationResult = try await authorizationController.performRequests([passkeyRegistrationRequest(username: username)], options: options)
            try await handleAuthorizationResult(authorizationResult, username: username)
        } catch let authorizationError as ASAuthorizationError where authorizationError.code == .canceled {
            // Handles user cancellation during registration
            print("The user cancelled passkey registration.")
            self.authzError = true
            self.authzErrorMessage = "The user cancelled passkey registration."
        } catch let authorizationError as ASAuthorizationError {
            // Handles other authorization errors during registration
            print("Passkey registration failed. Error: \(authorizationError.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey registration failed. Error: \(authorizationError.localizedDescription)"
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Handles unknown authorization results during registration
            print("Passkey registration handling failed. Received an unknown result: \(String(describing: authorizationResult))")
            self.authzError = true
            self.authzErrorMessage = "Passkey registration handling failed. Received an unknown result: \(String(describing: authorizationResult))"
        } catch AuthorizationHandlingError.duplicateError {
            // Handles duplicate enrollment error during registration
            print("Passkey registration handling failed. Received a duplicate enrollment error: \(AuthorizationHandlingError.duplicateError.errorDescription ?? "")")
            self.authzError = true
            self.authzErrorMessage = "Passkey registration handling failed. Received a duplicate enrollment error: \(String(describing: AuthorizationHandlingError.duplicateError.errorDescription))"
        } catch {
            // Handles unknown errors during registration
            print("Passkey registration handling failed. Caught an unknown error during passkey registration or handling: \(error.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey registration handling failed. Caught an unknown error during passkey registration or handling: \(error.localizedDescription)"
        }
    }
    
    /**
     Performs password account creation.
     
     - Parameters:
        - username: The username for registration.
        - password: The password for registration.
     */
    public func createPasswordAccount(username: String, password: String) async {
        // Sets the currentUser to an authenticated user with the provided username
        currentUser = .authenticated(username: username)
    }
    
    /**
     Signs out the current user.
     */
    public func signOut() {
        // Sets the currentUser to nil effectively removing the authenticated user
        currentUser = nil
    }
    
    // MARK: - Private
    
    private static let relyingPartyIdentifier = Helpers.readWebAuthnServerDomain()
    
    /**
     Performs a passkey assertion request and returns an ASAuthorizationRequest object.
     
     - Returns: An ASAuthorizationRequest object representing the passkey assertion request.
     */
    private func passkeyAssertionRequest() async -> ASAuthorizationRequest {
        // Sends a request to obtain the necessary parameters for the assertion request
        let parameters: [String: Any] = [
            "login": ""
        ]
        
        let data = try! await AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/login", method: .put,parameters: parameters, encoding: JSONEncoding.default,headers: ["Content-Type": "application/json"]).serializingDecodable(CredentialAssertion.self).value
        
        let challenge = data.publicKey.challenge.decodeBase64Url()!
        let credProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
        let assertionRequest = credProvider.createCredentialAssertionRequest(challenge: challenge)
        
        if let userVerification = data.publicKey.userVerification {
            assertionRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
        }
        
        return assertionRequest
    }
    
    /**
     Performs a passkey registration request and returns an ASAuthorizationRequest object.
     
     - Parameter username: The username for registration.
     - Returns: An ASAuthorizationRequest object representing the passkey registration request.
     */
    private func passkeyRegistrationRequest(username: String) async throws -> ASAuthorizationRequest {
        // Sends a request to register a passkey account and obtain the necessary parameters for the registration request
        let parameters: [String: Any] = [
            "login": username,
            "useResidentKey": false
        ]
        
        let request = AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/register",
                                 method: .put,
                                 parameters: parameters,
                                 encoding: JSONEncoding.default,
                                 headers: ["Content-Type": "application/json"])
        do {
            let response = await request.serializingDecodable(CredentialCreation.self).response
            if(response.response?.statusCode == 200) {
                let data = response.value!
                let challenge = data.publicKey.challenge.decodeBase64Url()!
                let credProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
                let userID = data.publicKey.user.id.decodeBase64Url()!
                let registrationRequest = credProvider.createCredentialRegistrationRequest(challenge: challenge, name: username, userID: userID)
                
                if let attestation = data.publicKey.attestation {
                    registrationRequest.attestationPreference = ASAuthorizationPublicKeyCredentialAttestationKind.init(rawValue: attestation)
                }
                
                if let userVerification = data.publicKey.authenticatorSelection?.userVerification {
                    registrationRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
                }
                
                return registrationRequest
            }
            else {
                if(response.response?.statusCode == 409) {
                    throw AuthorizationHandlingError.duplicateError
                }
                else {
                    throw AuthorizationHandlingError.otherError
                }
            }
            
        } catch {
            throw error
        }
    }
    
    /**
     Sends the registration response to the server.
     
     - Parameters:
        - params: The registration response parameters.
     - Returns: The login information obtained from the server response.
     - Throws: An error if there is a failure in the registration process or during the network request.
     */
    func sendRegistrationResponse(params: ASAuthorizationPlatformPublicKeyCredentialRegistration) async throws -> String {
        // Creates a registration response dictionary and sends the response to the server
        
        let response = [
            "attestationObject": params.rawAttestationObject!.toBase64Url(),
            "clientDataJSON": String(data: params.rawClientDataJSON, encoding: .utf8),
            "id": params.credentialID.toBase64Url()
        ]
        let parameters: Parameters = [
            "id": params.credentialID.toBase64Url(),
            "rawId": params.credentialID.toBase64Url(),
            "type": "public-key",
            "attestation": response
        ]
        
        let request = AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/make-new-credential",
                                 method: .put,
                                 parameters: parameters,
                                 encoding: JSONEncoding.default,
                                 headers: ["Content-Type": "application/json"])
        
        do {
            let response = request.serializingDecodable(CredentialCreationVerificationResponse.self)
            return try await response.value.login
        } catch {
            throw error
        }
    }
    
    /**
     Creates an array of ASAuthorizationRequest objects for sign-in.
     
     - Returns: An array of ASAuthorizationRequest objects representing the sign-in requests.
     */
    private func signInRequests() async -> [ASAuthorizationRequest] {
        // Creates an array of sign-in requests including passkey assertion and password provider
        await [passkeyAssertionRequest(), ASAuthorizationPasswordProvider().createRequest()]
    }
    
    /**
     Sends the authentication response to the server.
     
     - Parameters:
        - params: The authentication response parameters.
     - Returns: The login information obtained from the server response.
     - Throws: An error if there is a failure in the authentication process or during the network request.
     */
    func sendAuthenticationResponse(params: ASAuthorizationPlatformPublicKeyCredentialAssertion) async throws -> String {
        // Creates an authentication response dictionary and sends the response to the server
        let response = [
            "authenticatorData": params.rawAuthenticatorData.toBase64Url(),
            "clientDataJSON": String(data: params.rawClientDataJSON, encoding: .utf8),
            "signature": params.signature.toBase64Url(),
            "userHandle": params.userID.toBase64Url(),
            "id": params.credentialID.base64EncodedString(),
            "rawId": params.credentialID.toBase64Url(),
            "type": "public-key"
        ]
        let parameters: Parameters = [
            "assertion": response
        ]
        
        let request = AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/verify-assertion",
                                 method: .put,
                                 parameters: parameters,
                                 encoding: JSONEncoding.default)
        
        do {
            let response = request.serializingDecodable(CredentialCreationVerificationResponse.self)
            return try await response.value.login
        } catch {
            throw error
        }
    }
    
    // MARK: - Handle the results.
    
    /**
     Handles the authorization result from the authentication process.
     
     - Parameters:
        - authorizationResult: The authorization result from the authentication process.
        - username: The username used for registration (optional).
     */
    private func handleAuthorizationResult(_ authorizationResult: ASAuthorizationResult, username: String? = nil) async throws {
        // Handles different authorization results and performs necessary actions
        switch authorizationResult {
        case let .password(passwordCredential):
            // Password authorization succeeded
            print("Password authorization succeeded: \(passwordCredential)")
            currentUser = .authenticated(username: passwordCredential.user)
        case let .passkeyAssertion(passkeyAssertion):
            // Passkey authorization succeeded
            print("Passkey authorization succeeded: \(passkeyAssertion)")
            let pkAss = passkeyAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion
            print("A credential was used to authenticate: \(pkAss)")
            // Verify the assertion and sign the user in
            do {
                let login = try await sendAuthenticationResponse(params: pkAss)
                self.currentUser = .authenticated(username: login)
            } catch {
                print("Credential authentication failed: \(pkAss)")
                throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
            }
        case let .passkeyRegistration(passkeyRegistration):
            // Passkey registration succeeded
            let reg = passkeyRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration
            do {
                let login = try await sendRegistrationResponse(params: reg)
                if username == login {
                    self.currentUser = .authenticated(username: username!)
                }
                print("Passkey registration succeeded: \(passkeyRegistration)")
            } catch {
                print("Passkey registration failed: \(passkeyRegistration)")
                throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
            }
        default:
            // Received an unknown authorization result
            print("Received an unknown authorization result.")
            // Throw an error and return to the caller
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
        
        // In a real app, call the code at this location to obtain and save an authentication token to the keychain and sign in the user
    }
}

extension String {
    /**
     Decodes a base64 URL string into data.
     
     - Returns: The decoded data.
     */
    func decodeBase64Url() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        
        return Data(base64Encoded: base64)
    }
}

extension Data {
    /**
     Converts data to a base64 URL string.
     
     - Returns: The base64 URL string.
     */
    func toBase64Url() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#endif // os(iOS) || os(macOS)

