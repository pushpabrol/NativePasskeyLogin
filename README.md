# Passkey Login: A demo project

This a demo implementation of support for passkey in native apps

## What it does

This code shows how to use
    - The Domain Associations for webcredentials
    - Use of an external API for registration and authentication using passkeys
    
## How it works?

### Registration ( Sign Up)
    - Parameter username: The username for registration.
    - Posts a request to the /api/register endpoint of the server
    - The server checks the user does not already exist. If not it creates the user with a new id and returns a response with a challenge for credential enrollment
    - The app then invokes the Passkey Registration flow using the challenge 
    - The OS asks the user to use their biometrics to allow the generation of a credential and verification of it 
    - The app then takes the registration data and posts this to the server
        - The app posts an attestation with credential id and a few other data items to the /api/make-newcredential endpoint
        - The server saves the credential data against the user record 
        - Returns success message about user 
        
        
 ### Login
    - The app initiates the authentication process by requesting authentication from the server by calling the /api/login. 
        This could happen when a user tries to log in to the app
    - The server generates a challenge, similar to the registration process
        The only difference is that if this was not a usernameLess login then the server uses the username to lookup the user and with the challenge also sends the id of the credential that has been registered for the user
    - The app receives the challenge and forwards it to the authenticator.
    - The authenticator prompts the user for authentication ( and or user selection), such as a biometric scan, button press, or PIN entry, depending on the authenticator type.
     - If the user's authentication is successful, the authenticator uses the private key associated with the registered credential to sign the challenge, creating a digital signature.
     - The app collects the digital signature and sends it to the server/api (/api/verify-assertion) for authentication.
      - The server receives the digital signature and performs the necessary validations. This includes verifying the signature using the registered credential's public key and validating the user's identity.
      - If the signature is valid and the user's identity is confirmed, the server returns the success response to the app
      - User is logged in
        

