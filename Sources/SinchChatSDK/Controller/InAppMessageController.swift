import Foundation
import UIKit

protocol InAppMessageController {
    var queue: [Message] { get set }
    
    func showInAppMessage(messagePayload: [AnyHashable : Any]) -> Bool
    func replyToMessage(_ choice: ChoiceText)
    func closeMessage(_ message: Message)
}

class DefaultInAppMessageController: InAppMessageController, InAppMessageViewDelegate {
    
    var queue: [Message] = []
    var timer: Timer?
    var pushNotificationHandler: PushNotificationHandler
    var presentNewInAppMessageAfterInSec: Double = 0.5
    var checkIfAlertIsRemovedInSec: Double = 5.0
    
    init(pushNotificationHandler: PushNotificationHandler) {
        self.pushNotificationHandler = pushNotificationHandler
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
    
    func showInAppMessage(messagePayload: [AnyHashable : Any]) -> Bool {
        
        guard let message = parseMessage(payload: messagePayload) else { return false }
        
        DispatchQueue.main.async {
            
            self.queue.append(message)
            
            if self.queue.count > 1 {
                return
            }
            
            self.presentInAppMessage(message)
        }
        return true
    }
    
    func closeMessage(_ message: Message) {
        self.queue.removeFirst()

        DispatchQueue.main.asyncAfter(deadline: .now() + presentNewInAppMessageAfterInSec) {  [weak self] in
            
            guard let self = self else { return }
                        
            guard let nextMessage = self.queue.first else { return }
            
            self.presentInAppMessage(nextMessage)
            
        }
    }
    func replyToMessage(_ choice: ChoiceText) {
        
        pushNotificationHandler.pushRepository?.replyToMessageWithTextChoice(choice: choice) { _ in
            
        }
    }
    
    private func presentInAppMessage(_ message: Message) {
        
        guard  let viewController = WindowHelper.getVisibleController() else { return }
        
        if viewController is UIAlertController {
            self.timer = Timer.scheduledTimer(withTimeInterval: checkIfAlertIsRemovedInSec, repeats: false) { [weak self] _ in
                
                guard let self = self else { return }
                
                guard let nextMessage = self.queue.first else { return }
                self.presentInAppMessage(nextMessage)
            }
        } else {
            let inAppViewController = InAppMessageViewController(viewModel: DefaultInAppMessageViewModel(message: message),
                                                                 view: InAppMessageView(uiConfiguration: SinchSDKConfig.UIConfig.defaultValue,
                                                                                        localizationConfiguration: SinchSDKConfig.LocalizationConfig.defaultValue,
                                                                                        message: message))
            
            inAppViewController.delegate = self
            inAppViewController.modalPresentationStyle = .overFullScreen
            inAppViewController.modalTransitionStyle = .crossDissolve
            viewController.present(inAppViewController, animated: true, completion: nil)
            
        }
    }
    
    func parseMessage(payload: [AnyHashable : Any]) -> Message? {
        
            // missing entry id
        
        if let owner: String = payload["owner"] as? String, owner == "sinch" {
            
            guard let payloadData = payload["protobufPayload"] as? String,
                  let serializedData = Data(base64Encoded: payloadData) else {
                return nil
            }
            
            do {
                
                let incomingMessage =  try Sinch_Conversationapi_Type_AppMessage(serializedData: serializedData)
                switch incomingMessage.message {
                    
                case .textMessage(let message):
                    
                    return Message(entryId: "", owner: .incoming(nil), body: MessageText(text: message.text))
                case .mediaMessage(let mediaMessage):
                    
                    return Message(entryId: "", owner: .incoming(nil), body: MessageMedia(url: mediaMessage.url))
                case .locationMessage(let locationMessage):
                    
                    return Message(entryId: "", owner: .incoming(nil), body: MessageLocation(label: locationMessage.label,
                                                                                             title: locationMessage.title,
                                                                                             latitude: Double(locationMessage.coordinates.latitude),
                                                                                             longitude: Double(locationMessage.coordinates.longitude)))
                case .choiceMessage(let choiceMessageObject):
                    let choicesArray = DefaultMessageDataSource.createChoicesArray(choiceMessageObject.choices, entryID: "")
                    
                    return Message(entryId: "", owner: .incoming(nil), body: MessageChoices(text: choiceMessageObject.textMessage.text,
                                                                                            choices: choicesArray))
                case .cardMessage(let card):
                    let choicesArray = DefaultMessageDataSource.createChoicesArray(card.choices, entryID: "")
                    
                    return Message(entryId: "", owner: .incoming(nil), body: MessageCard(title: card.title,
                                                                                         description: card.description_p,
                                                                                         choices: choicesArray,
                                                                                         url: card.mediaMessage.url))
                case .carouselMessage(let carousel):
                    let choicesArray = DefaultMessageDataSource.createChoicesArray(carousel.choices, entryID: "")
                    var cardsArray: [MessageCard] = []
                    
                    for incomingCardMessage in carousel.cards {
                        
                        let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingCardMessage.choices, entryID: "")
                        
                        let messageBody = MessageCard(title: incomingCardMessage.title,
                                                      description: incomingCardMessage.description_p ,
                                                      choices: choicesArray,
                                                      url: incomingCardMessage.mediaMessage.url)
                        
                        cardsArray.append(messageBody)
                    }

                    return Message(entryId: "", owner: .incoming(nil), body: MessageCarousel(cards: cardsArray, choices: choicesArray))
                    
                default: return nil
                }
                                                
            } catch {
                debugPrint("error")
            }
        }
        
        return nil
    }
    
    private func handleIncomingMessage(_ entry: Sinch_Push_Dispatch_V1beta1_Payload) -> Message? {
        
        let dateReceived = Int64(Date().timeIntervalSince1970)
        
        // MARK: - Incoming messages
        
        let incomingText = entry.message.textMessage.text
        if !incomingText.isEmpty {
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                               body: MessageText(text: incomingText,
                                                 sendDate: dateReceived))
            } else {
                
                return Message(entryId: entry.trackingID, owner: .incoming(nil),
                               body: MessageText(text: incomingText,
                                                 sendDate: dateReceived))
            }
        }
        
        let incomingLocationMessage = entry.message.locationMessage
        if incomingLocationMessage.hasCoordinates {
            let messageBody = MessageLocation(label: incomingLocationMessage.label,
                                              title: incomingLocationMessage.title,
                                              latitude: Double(incomingLocationMessage.coordinates.latitude),
                                              longitude: Double(incomingLocationMessage.coordinates.longitude),
                                              sendDate: dateReceived)
            
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID,
                               owner: .incoming(.init(name: agent.displayName,
                                                      type: agent.type.rawValue)),
                               body:  messageBody)
            } else {
                
                return Message(entryId: entry.trackingID, owner: .incoming(nil), body: messageBody)
            }
        }
        
        let incomingChoiceMessage = entry.message.choiceMessage
        if incomingChoiceMessage.hasTextMessage {
            
            let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingChoiceMessage.choices, entryID: entry.trackingID)
            let messageBody = MessageChoices(text: incomingChoiceMessage.textMessage.text,
                                             choices: choicesArray,
                                             sendDate: dateReceived)
            
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                               body:  messageBody)
            } else {
                
                return Message(entryId: entry.trackingID, owner: .incoming(nil), body: messageBody)
            }
        }
        let incomingCardMessage = entry.message.cardMessage
        
        if incomingCardMessage.hasMediaMessage {
            
            let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingCardMessage.choices, entryID: entry.trackingID)
            let messageBody = MessageCard(title: incomingCardMessage.title,
                                          description: incomingCardMessage.description_p,
                                          choices: choicesArray,
                                          url: incomingCardMessage.mediaMessage.url,
                                          sendDate: dateReceived)
            
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID, owner: .incoming(.init(name: agent.displayName, type: agent.type.rawValue)),
                               body:  messageBody)
            } else {
                
                return Message(entryId: entry.trackingID, owner: .incoming(nil), body: messageBody)
            }
        }
        
        let incomingCarouselMessage = entry.message.carouselMessage
        
        if !incomingCarouselMessage.cards.isEmpty {
            
            let carouselChoicesArray = DefaultMessageDataSource.createChoicesArray(incomingCarouselMessage.choices, entryID: entry.trackingID)
            
            var cardsArray: [MessageCard] = []
            
            for incomingCardMessage in incomingCarouselMessage.cards {
                
                let choicesArray = DefaultMessageDataSource.createChoicesArray(incomingCardMessage.choices, entryID: entry.trackingID)
                
                let messageBody = MessageCard(title: incomingCardMessage.title,
                                              description: incomingCardMessage.description_p ,
                                              choices: choicesArray,
                                              url: incomingCardMessage.mediaMessage.url,
                                              sendDate: dateReceived)
                
                cardsArray.append(messageBody)
            }
            
            let messageBody = MessageCarousel(cards: cardsArray, choices: carouselChoicesArray, sendDate: dateReceived)
            
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID, owner: .incoming(.init(name: agent.displayName,
                                                                                 type: agent.type.rawValue)),
                               body:  messageBody)
            } else {
                
                return Message(entryId: entry.trackingID, owner: .incoming(nil), body: messageBody)
            }
        }
        
        let incomingUrl = entry.message.mediaMessage.url
        
        if !incomingUrl.isEmpty {
            if entry.message.hasAgent {
                let agent = entry.message.agent
                
                return Message(entryId: entry.trackingID, owner: .incoming(.init(name: agent.displayName,
                                                                                 type: agent.type.rawValue)),
                               body: MessageMedia(url: incomingUrl,
                                                  sendDate: dateReceived))
            } else {
                return Message(entryId: entry.trackingID, owner: .incoming(nil),
                               body: MessageMedia(url: incomingUrl,
                                                  sendDate: dateReceived))
            }
        }
        
        return nil
    }
}
