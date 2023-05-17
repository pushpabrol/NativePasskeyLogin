//
//  ContentView.swift
//  PasskeyLogin
//
//  Created by Pushp Abrol on 5/15/23.
//

import SwiftUI
import AuthenticationServices

struct ContentView: View {

    @ObservedObject var accountStore: AccountStore

    @Environment(\.authorizationController) private var authorizationController
    
    @State private var isSignUpSheetPresented = false
    @State private var isSignOutAlertPresented = false

    var body: some View {
        Form {
            if case let .authenticated(username) = accountStore.currentUser {
                Section {
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.accentColor.gradient, in: Circle())

                        Text(username)
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
            }

            Section {
                if accountStore.isSignedIn {
                    LabeledContent("Sign out") {
                        Button("Sign Out", role: .destructive) {
                            isSignOutAlertPresented = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .labelsHidden()
                } else {
                    
                    HStack {
                        Text("Use existing account")
                        Spacer()
                            Button("Sign In") {
                                Task {
                                    await signIn()
                                }
                            }
                        }
                    
                }
            } footer: {
                if !accountStore.isSignedIn {
                    Label("""
                    iOs will show an option to use the available passkeys for this app.
                    """, systemImage: "person.badge.key.fill")
                }
            }
            
            Section {
                if(!accountStore.isSignedIn){
                    LabeledContent("Create new account") {
                        Button("Sign Up") {
                            isSignUpSheetPresented = true
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .navigationDestination(for: String.self) { _ in
            LoggedInView()
        }
        .sheet(isPresented: $isSignUpSheetPresented) {
            NavigationStack {
                SignUpView().environmentObject(accountStore)
            }
        }
        .alert(isPresented: $isSignOutAlertPresented) {
            signOutAlert
        }
    }
    
    private func signIn() async {
        await accountStore.signIntoPasskeyAccount(authorizationController: authorizationController)
    }

    private var signOutAlert: Alert {
        Alert(
            title: Text("Are you sure you want to sign out?"),
            primaryButton: .destructive(Text("Sign Out")) {
                accountStore.signOut()
            },
            secondaryButton: .cancel()
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    struct Preview: View {
        @StateObject private var accountStore = AccountStore()
        var body: some View {
            ContentView(accountStore: accountStore)
        }
    }
    static var previews: some View {
        Preview()
    }
}
