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
    case unknownAuthorizationResult(ASAuthorizationResult)
    case otherError
    case duplicateError
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
            
        case .duplicateError:
            return NSLocalizedString("Encountered an error handling the registration.",
                                     comment: "A user with the same usernme already exists!")
        }
        
    }
}

@MainActor
public final class AccountStore: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    @Published public private(set) var currentUser: User? = .none
    public var authzError: Bool = false
    public private(set) var authzErrorMessage: String? = nil
    
    
    public var isSignedIn: Bool {
        currentUser != nil || currentUser != .none
    }
    
    /**
     Performs sign-in with passkey account.
     
     - Parameters:
        - authorizationController: The AuthorizationController instance.
        - options: Additional options for the authorization request.
     */
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
            self.authzError = true
            self.authzErrorMessage = "The user cancelled passkey authorization."
        } catch let authorizationError as ASAuthorizationError {
            // Some other error occurred occurred during authorization.
            print("Passkey authorization failed. Error: \(authorizationError.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey authorization failed. Error: \(authorizationError.localizedDescription)"
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Received an unknown response.
            print("""
            Passkey authorization handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """)
            self.authzError = true
            self.authzErrorMessage = """
            Passkey authorization handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """
        } catch {
            // Some other error occurred while handling the authorization.
            print("""
            Passkey authorization handling failed. \
            Caught an unknown error during passkey authorization or handling: \(error.localizedDescription)"
            """)
            self.authzError = true
            self.authzErrorMessage = """
            Passkey authorization handling failed. \
            Caught an unknown error during passkey authorization or handling: \(error.localizedDescription)"
            """
        }
    }
    
    /**
     Performs passkey account creation.
     
     - Parameters:
        - authorizationController: The AuthorizationController instance.
        - username: The username for registration.
        - options: Additional options for the authorization request.
     */
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
            self.authzError = true
            self.authzErrorMessage = "The user cancelled passkey registration."
            
        } catch let authorizationError as ASAuthorizationError {
            // Some other error occurred occurred during registration.
            print("Passkey registration failed. Error: \(authorizationError.localizedDescription)")
            self.authzError = true
            self.authzErrorMessage = "Passkey registration failed. Error: \(authorizationError.localizedDescription)"
        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
            // Received an unknown response.
            print("""
            Passkey registration handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """)
            self.authzError = true
            self.authzErrorMessage = """
            Passkey registration handling failed. \
            Received an unknown result: \(String(describing: authorizationResult))
            """
        } catch AuthorizationHandlingError.duplicateError {
            // Received an unknown response.
            print("""
            Passkey registration handling failed. \
            Received a duplicate enrollment error: \(AuthorizationHandlingError.duplicateError.errorDescription)
            """)
            self.authzError = true
            self.authzErrorMessage = """
            Passkey registration handling failed. \
            Received a duplicate enrollment error: \(AuthorizationHandlingError.duplicateError.errorDescription)
            """
        } catch {
            // Some other error occurred while handling the registration.
                print("""
                Passkey registration handling failed.
                Caught an unknown error during passkey registration or handling: (error.localizedDescription).
                """)
            self.authzError = true
            self.authzErrorMessage = """
                Passkey registration handling failed.
                Caught an unknown error during passkey registration or handling: (error.localizedDescription).
                """
            }
    }

/**
 Performs password account creation.
 
 - Parameters:
    - username: The username for registration.
    - password: The password for registration.
 */
public func createPasswordAccount(username: String, password: String) async {
    currentUser = .authenticated(username: username)
}

/**
 Signs out the current user.
 */
public func signOut() {
    currentUser = nil
}

// MARK: - Private

private static let relyingPartyIdentifier = "webauthn.desmaximus.com"

/**
 Performs a passkey assertion request and returns an ASAuthorizationRequest object.
 
 - Returns: An ASAuthorizationRequest object representing the passkey assertion request.
 */
private func passkeyAssertionRequest() async -> ASAuthorizationRequest {
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
private func passkeyRegistrationRequest(username: String) async throws -> ASAuthorizationRequest{
    let parameters: [String: Any] = [
        "login": username,
        "useResidentKey": false
    ]
    
    
        var request = AF.request("https://webauthn.desmaximus.com/api/register",
                                method: .put,
                                parameters: parameters,
                                encoding: JSONEncoding.default,
                                headers: ["Content-Type": "application/json"])
    
    do {
        let response = try await request.serializingDecodable(CredentialCreation.self).response
        if(response.response?.statusCode == 200) {
            let data = await response.value!
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
        
    }catch {
        throw error
    }
    
        let data = try await AF.request("https://webauthn.desmaximus.com/api/register",
                                         method: .put,
                                         parameters: parameters,
                                         encoding: JSONEncoding.default,
                                         headers: ["Content-Type": "application/json"])
            .serializingDecodable(CredentialCreation.self).value
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

/**
 Sends the registration response to the server.
 
 - Parameters:
    - params: The registration response parameters.
    - completionHandler: A completion handler to be called when the response is sent.
 */
//func sendRegistrationResponse(params: ASAuthorizationPlatformPublicKeyCredentialRegistration, completionHandler: @escaping (String) -> Void) {
//    let response = [
//        "attestationObject": params.rawAttestationObject!.toBase64Url(),
//        "clientDataJSON": String(data: params.rawClientDataJSON, encoding: .utf8),
//        "id": params.credentialID.toBase64Url()
//        ]
//        let parameters: Parameters = [
//        "id": params.credentialID.toBase64Url(),
//        "rawId": params.credentialID.toBase64Url(),
//        "type": "public-key",
//        "attestation": response
//        ]
//
////    let data = try! await AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/login", method: .put,parameters: parameters, encoding: JSONEncoding.default,headers: ["Content-Type": "application/json"]).serializingDecodable(CredentialAssertion.self).value
//
//    AF.request("https://\(AccountStore.relyingPartyIdentifier)/api/make-new-credential",
//               method: .put,
//               parameters: parameters,
//               encoding: JSONEncoding.default,
//               headers: ["Content-Type": "application/json"]).responseDecodable(of: MakeCredentialCreationResponse.self){ response in
//                    print(response)
//            //to get status code
//        if let status = response.response?.statusCode {
//            switch(status){
//            case 200:
//                print("example success")
//                if let result = response.value {
//                    completionHandler(result.login)
//                            }
//
//            default:
//                print("error with response status: \(status)")
//            }
//        }
//
//
//
//
//}
//}
    
    func sendRegistrationResponse(params: ASAuthorizationPlatformPublicKeyCredentialRegistration) async throws -> String {
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
    await [passkeyAssertionRequest(), ASAuthorizationPasswordProvider().createRequest()]
}

/**
 Sends the authentication response to the server.
 
 - Parameters:
    - params: The authentication response parameters.
    - completionHandler: A completion handler to be called when the response is sent.
 */
    func sendAuthenticationResponse(params: ASAuthorizationPlatformPublicKeyCredentialAssertion) async throws -> String {
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
    switch authorizationResult {
    case let .password(passwordCredential):
        // Password authorization succeeded.
        print("Password authorization succeeded: \(passwordCredential)")
        currentUser = .authenticated(username: passwordCredential.user)
    case let .passkeyAssertion(passkeyAssertion):
        // Passkey authorization succeeded.
        print("Passkey authorization succeeded: \(passkeyAssertion)")
        let pkAss = passkeyAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion
        print("A credential was used to authenticate: \(pkAss)")
        // Verify the assertion and sign the user in.
        
        do {
            let login = try await sendAuthenticationResponse(params: pkAss)
            self.currentUser = .authenticated(username: login)
        }
        catch {
            print("Credential authentication failed: \(pkAss)")
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    
    case let .passkeyRegistration(passkeyRegistration):
        // Passkey registration succeeded.
        let reg = passkeyRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration
        do {
            let login = try await sendRegistrationResponse(params: reg)
            if(username == login)
            {
                self.currentUser = .authenticated(username: username!)
            }
            
            print("Passkey registration succeeded: \(passkeyRegistration)")
        }catch {
            
            print("Passkey registration failed: \(passkeyRegistration)")

            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)

        }
    default:
        // Received an unknown authorization result.
        print("Received an unknown authorization result.")
        
        // Throw an error and return to the caller.
        throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
    }
    
    // In a real app, call the code at this location to obtain and save an authentication token to the keychain and sign in the user.
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


