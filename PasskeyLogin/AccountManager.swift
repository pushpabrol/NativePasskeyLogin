import SwiftUI
import AuthenticationServices
import Alamofire
import os

extension NSNotification.Name {
    static let UserSignedIn = Notification.Name("UserSignedInNotification")
}

class AccountManager: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    let domain = "webauthn.desmaximus.com" // TODO: insert your domain name here
    var authenticationAnchor: ASPresentationAnchor?
    
    func signInWith(userName: String?, anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)
        
        // Fetch the challenge from our webapp the server. It is unique for every request.
        getAuthenticationOptions(userName: userName) { assertionRequestOptions in
            let challenge = assertionRequestOptions.publicKey.challenge.decodeBase64Url()!
            let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)
            
            // Check if the webapp requires user verification (see https://docs.hanko.io/guides/userverification)
            if let userVerification = assertionRequestOptions.publicKey.userVerification {
                assertionRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
            }
            
            // you can pass in any mix of supported sign in request types here - we only use Passkeys
            let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
        }
    }
    
    func signUpWith(userName: String, anchor: ASPresentationAnchor) {
        self.authenticationAnchor = anchor
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)
        
        // Fetch the challenge from our webapp. The challenge is unique for every request.
        getRegistrationOptions(username: userName) { creationRequest in
            let challenge = creationRequest.publicKey.challenge.decodeBase64Url()!
            let userID = creationRequest.publicKey.user.id.decodeBase64Url()!
            let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
            // Check if the webapp requires attestation (see https://docs.hanko.io/guides/attestation)
            if let attestation = creationRequest.publicKey.attestation {
                registrationRequest.attestationPreference = ASAuthorizationPublicKeyCredentialAttestationKind.init(rawValue: attestation)
            }
            
            // Check if the webapp requires user verification (see https://docs.hanko.io/guides/userverification)
            if let userVerification = creationRequest.publicKey.authenticatorSelection?.userVerification {
                registrationRequest.userVerificationPreference = ASAuthorizationPublicKeyCredentialUserVerificationPreference.init(rawValue: userVerification)
            }
            
            let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let logger = Logger()
        switch authorization.credential {
        case let credentialRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            logger.log("A new credential was registered: \(credentialRegistration)")
            
            // After the webapp has verified the registration and created the user account, sign the user in with the new account.
            sendRegistrationResponse(params: credentialRegistration) {
                self.didFinishSignIn()
            }
        case let credentialAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            logger.log("A credential was used to authenticate: \(credentialAssertion)")
            
            // After the server has verified the assertion, sign the user in.
            sendAuthenticationResponse(params: credentialAssertion) {
                self.didFinishSignIn()
            }
        default:
            fatalError("Received unknown authorization type.")
        }
    }
    
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let logger = Logger()
        guard let authorizationError = ASAuthorizationError.Code(rawValue: (error as NSError).code) else {
            logger.error("Unexpected authorization error: \(error.localizedDescription)")
            return
        }
        
        if authorizationError == .canceled {
            // Either no credentials were found and the request silently ended, or the user canceled the request.
            // Consider asking the user to create an account.
            logger.log("Request canceled.")
        } else {
            // Other ASAuthorization error.
            // The userInfo dictionary should contain useful information.
            logger.error("Error: \((error as NSError).userInfo)")
        }
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return authenticationAnchor!
    }
    
    func didFinishSignIn() {
        NotificationCenter.default.post(name: .UserSignedIn, object: nil)
    }
    
    // Initialize a user account and credential registration
    // see https://github.com/teamhanko/apple-wwdc21-webauthn-example/blob/master/main.go
    func getRegistrationOptions(username: String, completionHandler: @escaping (CredentialCreation) -> Void) {
        register(username: username, useResidentKey: false) { credCreation in
            completionHandler(credCreation)
        }
    }
    
    func register(username: String, useResidentKey: Bool, completion: @escaping (CredentialCreation) -> Void) {
        let parameters: [String: Any] = [        "login": username,        "useResidentKey": useResidentKey    ]
        
        AF.request("https://webauthn.desmaximus.com/api/register", method: .put, parameters: parameters, encoding: JSONEncoding.default, headers: ["Content-Type": "application/json"])
            .validate()
            .responseDecodable(of: CredentialCreation.self) { response in
                if let value = response.value {
                    completion(value)
                }
            }
    }
    
    // Finalize the user account and credential registration
    // see https://github.com/teamhanko/apple-wwdc21-webauthn-example/blob/master/main.go
    func sendRegistrationResponse(params: ASAuthorizationPlatformPublicKeyCredentialRegistration, completionHandler: @escaping () -> Void) {
        let response = [ "attestationObject": params.rawAttestationObject!.toBase64Url(),        "clientDataJSON": String(data: params.rawClientDataJSON, encoding: .utf8),        "id": params.credentialID.toBase64Url()    ]
        let parameters: Parameters = [        "id": params.credentialID.toBase64Url(),        "rawId": params.credentialID.toBase64Url(),        "type": "public-key",        "attestation": response    ]
        AF.request("https://\(domain)/api/make-new-credential", method: .put, parameters: parameters, encoding: JSONEncoding.default, headers: ["Content-Type": "application/json"]).response { response in
            if response.response?.statusCode == 200 {
                completionHandler()
            } else {
                Logger().error("Error: \(response.error?.errorDescription ?? "unknown error")")
            }
        }
    }
    
    // Initialize user authentication
    // see https://github.com/teamhanko/apple-wwdc21-webauthn-example/blob/master/main.go
    func getAuthenticationOptions(userName: String?, completionHandler: @escaping (CredentialAssertion) -> Void) {
        let parameters: [String: Any] = [
            "login": userName ?? ""
        ]
        AF.request("https://(domain)/api/login", method: .put, parameters: parameters, encoding: JSONEncoding.default, headers: ["Content-Type": "application/json"]).responseDecodable(of: CredentialAssertion.self) { response in
            if let value = response.value {
                completionHandler(value)
            } else {
                print(response.error?.errorDescription ?? "unknown error")
            }
        }
    }
    
    
    
    // Finalize user authentication
    // see https://github.com/teamhanko/apple-wwdc21-webauthn-example/blob/master/main.go
    func sendAuthenticationResponse(params: ASAuthorizationPlatformPublicKeyCredentialAssertion, completionHandler: @escaping () -> Void) {
        let response = [        "authenticatorData": params.rawAuthenticatorData.toBase64Url(),        "clientDataJSON": String(data: params.rawClientDataJSON, encoding: .utf8),        "signature": params.signature.toBase64Url(),        "userHandle": params.userID.toBase64Url(),        "id": params.credentialID.base64EncodedString(),        "rawId": params.credentialID.toBase64Url(),        "type": "public-key"    ]
        let parameters: Parameters = [        "assertion": response    ]
        AF.request("https://\(domain)/api/verify-assertion", method: .put, parameters: parameters, encoding: JSONEncoding.default).response { response in
            if response.response?.statusCode == 200 {
                completionHandler()
            } else {
                Logger().error("Error: \(response.error?.errorDescription ?? "unknown error")")
            }
        }
    }
    
}

extension String {
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
func toBase64Url() -> String {
return self.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
}






