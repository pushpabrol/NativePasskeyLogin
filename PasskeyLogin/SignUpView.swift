
import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    private enum FocusElement {
        case username
        case password
    }

    private enum SignUpType {
        case passkey
        case password
    }


    @EnvironmentObject private var accountStore: AccountStore
    @Environment(\.authorizationController) private var authorizationController
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedElement: FocusElement?
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("User name") {
                    TextField("User name", text: $username)
                        .textContentType(.username)
                        .multilineTextAlignment(.trailing)
#if os(iOS)
                    
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
#endif
                        .focused($focusedElement, equals: .username)
                        .labelsHidden()
                }
                

            } header: {
                Text("Create an account")
            } footer: {
                Label("""
                    When you sign up with a passkey, all you need is a user name. \
                    The passkey will be available on all of your devices.
                    """, systemImage: "person.badge.key.fill")
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: true)
        .navigationTitle("Sign up")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sign Up") {
                    Task {
                        await signUp()
                    }
                }
                .disabled(!isFormValid)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    print("Canceled sign up.")
                    dismiss()
                }
            }
        }
        .onAppear {
            focusedElement = .username
        }.alert(isPresented: $accountStore.authzError){
            errorAlert
        }
    }

    private func signUp() async {
        Task {
                await accountStore.createPasskeyAccount(authorizationController: authorizationController, username: username)
        
            if(!accountStore.authzError) {
                dismiss()
            }
        }
    }

    private var isFormValid: Bool {

            return !username.isEmpty
    }
    
    private var errorAlert: Alert {
        Alert(
            title: Text(accountStore.authzErrorMessage!),
            primaryButton: .destructive(Text("Ok")) {
                dismiss()
            },
            secondaryButton: .cancel()
        )
    }
}

struct SignUpView_Previews: PreviewProvider {
    struct Preview: View {
        @StateObject private var accountStore = AccountStore()

        var body: some View {
            SignUpView()
                .environmentObject(accountStore)
        }
    }

    static var previews: some View {
        NavigationStack {
            Preview()
        }
    }
}

