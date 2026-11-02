import Foundation
import Supabase

/// Server errors reduced to a code the UI can turn into a plain sentence.
nonisolated struct APIError: LocalizedError, Equatable {
    let code: String
    let underlying: String

    init(code: String, underlying: String = "") {
        self.code = code
        self.underlying = underlying
    }

    init(_ error: Error) {
        if let e = error as? APIError {
            self = e
        } else if let e = error as? PostgrestError {
            self.init(code: e.message, underlying: e.code ?? "")
        } else if let e = error as? AuthError {
            self.init(code: APIError.authCode(from: e), underlying: e.localizedDescription)
        } else if let e = error as? FunctionsError {
            switch e {
            case .httpError(let status, let data):
                let body = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                self.init(code: body ?? "http_\(status)", underlying: "")
            case .relayError:
                self.init(code: "relay_error")
            }
        } else if (error as NSError).domain == NSURLErrorDomain {
            self.init(code: "offline", underlying: error.localizedDescription)
        } else {
            self.init(code: "unknown", underlying: String(describing: error))
        }
    }

    private static func authCode(from error: AuthError) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("only us phone numbers") { return "non_us_number" }
        if text.contains("expired") || text.contains("invalid") || text.contains("otp") { return "bad_code" }
        if text.contains("rate") { return "too_many_attempts" }
        return "auth_failed"
    }

    var errorDescription: String? { message }

    /// Copy aimed at a non-technical relative.
    var message: String {
        switch code {
        case "not_signed_in": return "Please sign in again."
        case "name_required": return "Please enter your first and last name."
        case "non_us_number": return "Only US phone numbers can sign up right now."
        case "bad_code": return "That code didn't work. Check the text and try again."
        case "too_many_attempts": return "Too many tries. Please wait a few minutes and try again."
        case "not_eligible": return "You can only request people whose number is saved in your contacts."
        case "already_following": return "You already follow this person."
        case "request_pending": return "You've already sent a request."
        case "request_not_found": return "That request isn't there any more."
        case "cannot_follow_self": return "That's you!"
        case "media_count_invalid": return "Choose between 1 and 10 photos or videos."
        case "video_too_long": return "Videos can be up to 60 seconds long."
        case "caption_too_long": return "Captions can be up to 1,000 characters."
        case "media_not_ready": return "Your photos are still uploading. Please wait a moment."
        case "post_not_found": return "That post isn't available."
        case "story_not_found": return "That story isn't available any more."
        case "own_post", "own_story": return "You can't message yourself."
        case "responses_off": return "This person has turned off responses for this post."
        case "replies_off": return "This person has turned off replies for this story."
        case "conversation_read_only": return "You can't send messages here any more because neither of you follows the other."
        case "conversation_not_found", "message_not_found": return "That conversation isn't available."
        case "message_empty": return "Type a message first."
        case "message_too_long": return "Messages can be up to 2,000 characters."
        case "not_following": return "Follow this person first to turn on notifications."
        case "offline": return "You seem to be offline. Check your connection and try again."
        case "profile_not_found": return "That person isn't available."
        default: return "Something went wrong. Please try again."
        }
    }
}
