import Foundation
import CommonCrypto

public extension String {

    func hmac(algorithm: CryptoAlgorithm, key: String) -> String {
        let str = self.cString(using: String.Encoding.utf8)
        let strLen = Int(self.lengthOfBytes(using: String.Encoding.utf8))
        let digestLen = algorithm.digestLength
        let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLen)
        let keyStr = key.cString(using: String.Encoding.utf8)
        let keyLen = Int(key.lengthOfBytes(using: String.Encoding.utf8))

        CCHmac(algorithm.HMACAlgorithm, keyStr!, keyLen, str!, strLen, result)

        let digest = stringFromResult(result: result, length: digestLen)

        result.deallocate()

        return digest
    }

    private func stringFromResult(result: UnsafeMutablePointer<CUnsignedChar>, length: Int) -> String {
        let hash = NSMutableString()
        for counter in 0..<length {
            hash.appendFormat("%02x", result[counter])
        }
        return String(hash).lowercased()
    }
    
    func convertToValidFileName() -> String {
   // https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-keys.html
           let invalidFileNameCharactersRegex = "[^a-zA-Z0-9_.!()*+']"
           let fullRange = startIndex..<endIndex
           let validName = replacingOccurrences(of: invalidFileNameCharactersRegex,
                                                with: "-",
                                                options: .regularExpression,
                                                range: fullRange)
           return validName
    }
   
}
