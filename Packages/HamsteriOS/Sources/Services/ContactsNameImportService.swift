import Contacts
import Foundation
import HamsterKit

/// Explicit, local-only contact-name import. No phone/email/photo/note fields are requested.
public enum ContactsNameImportService {
  public struct Result { public let names: [String]; public let denied: Bool }
  public static func importNames() async throws -> Result {
    let store = CNContactStore()
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined { _ = try await store.requestAccess(for: .contacts) }
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      return Result(names: [], denied: true)
    }
    let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor]
    let request = CNContactFetchRequest(keysToFetch: keys)
    var names = Set<String>()
    try store.enumerateContacts(with: request) { contact, _ in
      let name = (contact.familyName + contact.givenName).trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { names.insert(name) }
    }
    return Result(names: names.sorted(), denied: false)
  }
}
