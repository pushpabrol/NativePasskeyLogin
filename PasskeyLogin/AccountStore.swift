/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
AccountStore manages account sign in and out.
*/

#if os(iOS) || os(macOS)

import AuthenticationServices
import SwiftUI
import Combine
import os
import Alamofire

public enum AuthorizationHandlingError: Error {
    case unknownAuthorizationResult(ASAuthorizationResult)
    case otherError
}

extension AuthorizationHandlingError: LocalizedError {
    public var errorDescription: String? {
            switch self {
            case .unknownAuthorizationResult:
                return NSLocalizedString("Received an unknown authorization result.",
                                         comment: "Human readable description of receiving an unknown authorization result.")
            case .otherError:
                return NSLocalizedString("Encountered an error handling the authorization result.",
                                         comment: "Human readable description of an unknown error while handling the authorization result.")
            }
        }
}

@MainActor
public final class AccountStore: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    @Published public private(set) var currentUser: User? = .none
    
    let domain = "webauthn.desmaximus.com"
    
    public var isSignedIn: Bool {
        currentUser != nil || currentUser != .none
    }
    
    public func signIntoPasskeyAccount(authorizationController: AuthorizationController,
                                       options: ASAuthorizationController.RequestOptions = []) async {
        do {
            let authorizationResult = try await authorizationController.performRequests(
                    signInRequests(),
                    options: options
            )
            try await handleAuthorizationResult(authorizationResult)
        } catch let authorizationError as ASAuthorizationError where authorizationError.code == .canceled {
            // The user cancelled the authorization.
            print("The user cancelled passkey authorization.")
        } catch let authorizationError as ASAuthorizationError {
            // Some other error occurred occurred during authorization.
            print("Passkey authorization failed. Error: \(authorizationError.localizedDescription)")
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Received an unknown response.
            print("""
            Passkey authorization handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """)
        } catch {
            // Some other error occurred while handling the authorization.
            print("""
            Passkey authorization handling failed. \
            Caught an unknown error during passkey authorization or handling: \(error.localizedDescription)"
            """)
        }
    }
    
    public func createPasskeyAccount(authorizationController: AuthorizationController, username: String,
                                     options: ASAuthorizationController.RequestOptions = []) async {
        do {
            let authorizationResult = try await authorizationController.performRequests(
                    [passkeyRegistrationRequest(username: username)],
                    options: options
            )
            try await handleAuthorizationResult(authorizationResult, username: username)
        } catch let authorizationError as ASAuthorizationError where authorizationError.code == .canceled {
            // The user cancelled the registration.
            print("The user cancelled passkey registration.")
        } catch let authorizationError as ASAuthorizationError {
            // Some other error occurred occurred during registration.
            print("Passkey registration failed. Error: \(authorizationError.localizedDescription)")
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Received an unknown response.
            print("""
            Passkey registration handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """)
        } catch {
            // Some other error occurred while handling the registration.
            print("""
            Passkey registration handling failed. \
            Caught an unknown error during passkey registration or handling: \(error.localizedDescription).
            """)
        }
    }

    public func createPasswordAccount(username: String, password: String) async {
        currentUser = .authenticated(username: username)
    }

    public func signOut() {
        currentUser = nil
    }

    // MARK: - Private

    private static let relyingPartyIdentifier = "webauthn.desmaximus.com"


    private func passkeyAssertionRequest() async -> ASAuthorizationRequest {
        let parameters: [String: Any] = [
            "login": ""
        ]
        
        let data = try! await AF.request("https://\(domain)/api/login", method: .put,parameters: parameters, encoding: JSONEncoding.default,headers: ["Content-Type": "application/json"]).serializingDecodable(CredentialAssertion.self).value
        
        let challenge = data.publicKey.challenge.decodeBase64Url()!
        let credProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
        let assertionRequest = credProvider.createCredentialAssertionRequest(challenge: challenge)
        
        if let userVerification = data.publicKey.userVerification {
            assertionRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
        }
        return assertionRequest;
        
    }

    private func passkeyRegistrationRequest(username: String) async -> ASAuthorizationRequest {
        
        // start registration request and get challenge
        
        let parameters: [String: Any] = [
            "login": username,
            "useResidentKey": false
        ]
        
        let data = try! await AF.request("https://webauthn.desmaximus.com/api/register",
                   method: .put,
                   parameters: parameters,
                   encoding: JSONEncoding.default,
                                       headers: ["Content-Type": "application/json"]).serializingDecodable(CredentialCreation.self).value

        let challenge = data.publicKey.challenge.decodeBase64Url()!
        let credProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
        let userID = data.publicKey.user.id.decodeBase64Url()!
        let registrationRequest = credProvider.createCredentialRegistrationRequest(challenge: challenge,name: username, userID: userID)
        
        if let attestation = data.publicKey.attestation {
            registrationRequest.attestationPreference = ASAuthorizationPublicKeyCredentialAttestationKind.init(rawValue: attestation)
            }
            
            if let userVerification = data.publicKey.authenticatorSelection?.userVerification {
                registrationRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
            }
        return registrationRequest
        

    }
    
    func sendRegistrationResponse(params: ASAuthorizationPlatformPublicKeyCredentialRegistration, completionHandler: @escaping () -> Void) {
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
        AF.request("https://\(domain)/api/make-new-credential", method: .put, parameters: parameters, encoding: JSONEncoding.default,headers: ["Content-Type": "application/json"]).response { response in
            if (response.response?.statusCode == 200) {
                completionHandler()
            } else {
                print("Error: \(response.error?.errorDescription ?? "unknown error")")
            }
        }
    }

    private func signInRequests() async -> [ASAuthorizationRequest] {
        await [passkeyAssertionRequest(), ASAuthorizationPasswordProvider().createRequest()]
    }
    
    func sendAuthenticationResponse(params: ASAuthorizationPlatformPublicKeyCredentialAssertion, completionHandler: @escaping () -> Void) {
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
        AF.request("https://\(domain)/api/verify-assertion", method: .put, parameters: parameters, encoding: JSONEncoding.default).response { response in
            if (response.response?.statusCode == 200) {
                completionHandler()
            } else {
                Logger().error("Error: \(response.error?.errorDescription ?? "unknown error")")
            }
        }
    }

    // MARK: - Handle the results.
    
    private func handleAuthorizationResult(_ authorizationResult: ASAuthorizationResult, username: String? = nil) async throws {
        
        
        switch authorizationResult {
            
        case let .password(passwordCredential):
            print("Password authorization succeeded: \(passwordCredential)")
            currentUser = .authenticated(username: passwordCredential.user)
        case let .passkeyAssertion(passkeyAssertion):
            // The login was successful.
            print("Passkey authorization succeeded: \(passkeyAssertion)")
            
                let pkAss = passkeyAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion
                print("A credential was used to authenticate: \(pkAss)")
                // After the server has verified the assertion, sign the user in.
                sendAuthenticationResponse(params: pkAss) {
                    guard let username = String(bytes: pkAss.userID, encoding: .utf8) else {
                        fatalError("Invalid credential: \(passkeyAssertion)")
                    }
                    self.currentUser = .authenticated(username: username)
                }
            
            

        case let .passkeyRegistration(passkeyRegistration):
            // The registration was successful.
            let reg = passkeyRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration
            sendRegistrationResponse(params: reg) {
                
                if let username {
                    self.currentUser = .authenticated(username: username)
                }
                    }
            print("Passkey registration succeeded: \(passkeyRegistration)")
            

        default:
            print("Received an unknown authorization result.")
            // Throw an error and return to the caller.
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
        
        // In a real app, call the code at this location to obtain and save an authentication token to the keychain and sign in the user.
    }
}

#endif // os(iOS) || os(macOS)

