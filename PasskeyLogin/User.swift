



public enum User : Equatable {
    case `default`
    case authenticated(username: String)

    public init(username: String) {
        self = .authenticated(username: username)
    }
}
