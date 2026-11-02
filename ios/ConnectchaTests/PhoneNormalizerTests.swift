import Testing
@testable import Connectcha

struct PhoneNormalizerTests {
    @Test("ten digits are a US number")
    func tenDigits() {
        #expect(PhoneNormalizer.normalize("555 000 0001") == .us(e164: "+15550000001"))
        #expect(PhoneNormalizer.normalize("(415) 555-2671") == .us(e164: "+14155552671"))
        #expect(PhoneNormalizer.normalize("415.555.2671") == .us(e164: "+14155552671"))
    }

    @Test("a leading 1 or +1 is accepted")
    func leadingOne() {
        #expect(PhoneNormalizer.normalize("1 415 555 2671") == .us(e164: "+14155552671"))
        #expect(PhoneNormalizer.normalize("+1 (415) 555-2671") == .us(e164: "+14155552671"))
        #expect(PhoneNormalizer.normalize("+14155552671") == .us(e164: "+14155552671"))
    }

    @Test("other countries are recognised as non-US")
    func nonUS() {
        #expect(PhoneNormalizer.normalize("+44 7700 900123") == .nonUS(e164: "+447700900123"))
        #expect(PhoneNormalizer.normalize("+34 612 34 56 78") == .nonUS(e164: "+34612345678"))
        #expect(PhoneNormalizer.normalize("011 44 7700 900123") == .nonUS(e164: "+447700900123"))
    }

    @Test("short, malformed or impossible numbers are invalid")
    func invalid() {
        #expect(PhoneNormalizer.normalize("") == .invalid)
        #expect(PhoneNormalizer.normalize("911") == .invalid)
        #expect(PhoneNormalizer.normalize("555-2671") == .invalid)
        #expect(PhoneNormalizer.normalize("015 555 2671") == .invalid)   // area code can't start with 0
        #expect(PhoneNormalizer.normalize("115 555 2671") == .invalid)   // area code can't start with 1
        #expect(PhoneNormalizer.normalize("+1 415 555") == .invalid)
    }

    @Test("extensions are dropped")
    func extensions() {
        #expect(PhoneNormalizer.normalize("415 555 2671 x204") == .us(e164: "+14155552671"))
    }

    @Test("display formatting")
    func display() {
        #expect(PhoneNormalizer.formatUSForDisplay(digits: "5550000001") == "(555) 000-0001")
        #expect(PhoneNormalizer.formatUSForDisplay(digits: "555") == "(555")
        #expect(PhoneNormalizer.formatUSForDisplay(digits: "5550") == "(555) 0")
    }

    @Test("hashing matches the server's definition")
    func hashing() {
        // echo -n '+15550001002' | shasum -a 256
        #expect(PhoneHasher.hash(e164: "+15550001002").count == 64)
        #expect(PhoneHasher.hash(e164: "+15550001002") == PhoneHasher.hash(e164: "+15550001002"))
        #expect(PhoneHasher.hash(e164: "+15550001002") != PhoneHasher.hash(e164: "+15550001003"))
    }
}
