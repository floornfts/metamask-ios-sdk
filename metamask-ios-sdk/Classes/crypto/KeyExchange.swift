//
//  KeyExchange.swift
//  
//
//  Created by Mpendulo Ndlovu on 2022/11/01.
//

import Foundation
import SocketIO

public enum KeyExchangeType: String, Codable {
    case none = "none"
    case start = "key_handshake_start"
    case ack = "key_handshake_ACK"
    case syn = "key_handshake_SYN"
    case synack = "key_handshake_SYNACK"
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
            case "none": self = .none
            case "key_handshake_start": self = .start
            case "key_handshake_ACK": self = .ack
            case "key_handshake_SYN": self = .syn
            case "key_handshake_SYNACK": self = .synack
            default:
                self = .none
          }
      }
}

public enum KeyExchangeError: Error {
    case keysNotExchanged
    case encodingError
}

public struct KeyExchangeMessage: CodableSocketData {
    public let type: KeyExchangeType
    public let pubkey: String?
    
    public func socketRepresentation() -> NetworkData {
        ["type": type.rawValue, "pubkey": pubkey]
    }
}

/*
 A module for handling key exchange between client and server
 The key exchange sequence is defined as:
 syn -> synack -> ack
 */

public class KeyExchange {
    private let privateKey: String
    public let pubkey: String
    public private(set) var theirPublicKey: String?
    
    private let encyption: Crypto.Type
    var keysExchanged: Bool = false
    
    public init(encryption: Crypto.Type = ECIES.self) {
        self.encyption = encryption
        self.privateKey = encyption.generatePrivateKey()
        self.pubkey = encyption.publicKey(from: privateKey)
    }
    
    func nextMessage(_ message: KeyExchangeMessage) -> KeyExchangeMessage? {
        switch message.type {
        case .syn:
            if let publicKey = message.pubkey {
                setTheirPublicKey(publicKey)
            }
            
            return KeyExchangeMessage(
                type: .synack,
                pubkey: pubkey)
            
        case .synack:
            
            if let publicKey = message.pubkey {
                setTheirPublicKey(publicKey)
            }
            
            keysExchanged = true

            return KeyExchangeMessage(
                type: .ack,
                pubkey: pubkey)
            
        case .ack:
            keysExchanged = true
            return nil
            
        default:
            Logging.error("Unknown key exchange")
            return nil
        }
    }
    
    public func message(type: KeyExchangeType) -> KeyExchangeMessage {
        KeyExchangeMessage(
            type: type,
            pubkey: pubkey
        )
    }
    
    public func setTheirPublicKey(_ publicKey: String?) {
        theirPublicKey = publicKey
    }
    
    public func encryptMessage<T: CodableData>(_ message: T) throws -> String {
        guard let theirPublicKey = theirPublicKey else {
            throw KeyExchangeError.keysNotExchanged
        }
        
        guard let encodedData = try? JSONEncoder().encode(message) else {
            throw KeyExchangeError.encodingError
        }
        
        guard let jsonString = String(
            data: encodedData,
            encoding: .utf8) else {
            throw KeyExchangeError.encodingError
        }
        
        Logging.log("Encrypting JSON: \(jsonString) with their key \(theirPublicKey)")
        
        return try encyption.encrypt(
            jsonString,
            publicKey: theirPublicKey
        )
    }
    
    public func decryptMessage(_ message: String) throws -> String {
        guard theirPublicKey != nil else {
            throw KeyExchangeError.keysNotExchanged
        }
        
        return try encyption.decrypt(
            message,
            privateKey: privateKey
        )
    }
}
