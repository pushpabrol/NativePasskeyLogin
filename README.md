# Passkey Login: A demo project

This a demo implementation of support for passkey in native apps. This uses a server for passkey registration and login at https://webauthn.desmaximus.com

## What it does

This code shows how to use
    - The Domain Associations for webcredentials
    - Use of an external API for registration and authentication using passkeys
    
## How it works?

### AccountStore.swift

    1. signIntoPasskeyAccount(authorizationController:options:): This method performs sign-in with a passkey account. It takes an AuthorizationController instance and additional options for the authorization request. Inside the method, it tries to perform the sign-in requests using authorizationController.performRequests(). If the authorization is successful, it calls the handleAuthorizationResult(authorizationResult:) method. If there are any errors during the sign-in process, it catches the specific types of errors, sets the authzError property to true, and assigns an appropriate error message to authzErrorMessage.

    2. createPasskeyAccount(authorizationController:username:options:): This method performs passkey account creation. It takes an AuthorizationController instance, a username, and additional options for the authorization request. Inside the method, it tries to perform the registration request using authorizationController.performRequests(). If the registration is successful, it calls the handleAuthorizationResult(authorizationResult:username:) method. If there are any errors during the registration process, it catches the specific types of errors, sets the authzError property to true, and assigns an appropriate error message to authzErrorMessage.

    3. createPasswordAccount(username:password:): This method performs password account creation. It takes a username and password as parameters. It sets the currentUser property to an authenticated user with the provided username.

    4. signOut(): This method signs out the current user by setting the currentUser property to nil, effectively removing the authenticated user.

    5. passkeyAssertionRequest(): This method performs a passkey assertion request. It sends a network request to obtain the necessary parameters for the assertion request. It uses Alamofire to make the request to a specific URL and receives a response containing the required data. It then creates an ASAuthorizationPlatformPublicKeyCredentialProvider instance and uses it to create an ASAuthorizationRequest object representing the passkey assertion request. The obtained data, such as the challenge and user verification preference, is set on the request object before returning it.

    6. passkeyRegistrationRequest(username:): This method performs a passkey registration request. It sends a network request to register a passkey account and obtain the necessary parameters for the registration request. Similar to the passkeyAssertionRequest() method, it uses Alamofire to make the request and receives a response containing the required data. It then creates an ASAuthorizationPlatformPublicKeyCredentialProvider instance and uses it to create an ASAuthorizationRequest object representing the passkey registration request. The obtained data, such as the challenge, attestation preference, and user verification preference, is set on the request object before returning it. If the registration request encounters an error, such as a duplicate username, it throws a specific AuthorizationHandlingError.

    7. sendRegistrationResponse(params:): This method sends the registration response to the server. It takes the registration response parameters as input. It uses Alamofire to send a request to a specific URL with the provided parameters. If the response has a status code of 200, it extracts the login information from the response and returns it. If the response has a status code of 409, indicating a duplicate enrollment error, it throws the AuthorizationHandlingError.duplicateError. Otherwise, it throws the AuthorizationHandlingError.otherError.

    8. sendAuthenticationResponse(params:): This method sends the authentication response to the server. It takes the authentication response parameters as input. It uses Alamofire to send a request to a specific URL with the provided parameters. If the response has a status code of 200, it extracts the login information from the response and returns it. If the response has any other status code, it throws an error.

    9. handleAuthorizationResult(authorizationResult:username:): This method handles the authorization result from the authentication process. It takes an ASAuthorizationResult object and an optional username used for registration. It switches over the different types of authorization results (password, passkey assertion, passkey registration). For password authorization, it sets the currentUser property to an authenticated user with the provided username. For passkey assertion and registration, it verifies the assertion or registration response by calling the appropriate sendAuthenticationResponse(params:) or sendRegistrationResponse(params:) methods. If the verification is successful, it updates the currentUser property. If there are any errors, it throws a specific AuthorizationHandlingError.

    10. signInRequests(): This method creates an array of ASAuthorizationRequest objects for sign-in. It calls the passkeyAssertionRequest() method to obtain the passkey assertion request and uses ASAuthorizationPasswordProvider().createRequest() to create a request for password authorization. It returns an array containing both request objects.

    11. String.decodeBase64Url(): This extension method decodes a base64 URL string into Data. It replaces the URL-safe characters '-' and '_' with '+' and '/', respectively, and adds padding characters if needed. Then it uses Data(base64Encoded:) to decode the modified base64 string and returns the resulting Data object.

    12. Data.toBase64Url(): This extension method converts Data to a base64 URL string. It uses base64EncodedString() to obtain the base64 representation of the data, and then replaces the characters '+' and '/' with '-' and '_', respectively. Finally, it removes any padding characters '=' and returns the modified base64 URL string.

        These methods provide the necessary functionality for managing account sign-in, registration, and handling authorization responses in the AccountStore class.
        

