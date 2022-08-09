import UIKit

protocol ComposeViewDelegate: AnyObject {
    
    func sendMessage(text: String)
    func sendChoiceResponseMessage(postbackData: String, entryID: String)
    func choosePhoto()
    func chooseAction()
}

final class ComposeView: SinchView {
    
    private let maxHeight: CGFloat = 125.0
    private let minHeight: CGFloat = 60.0
    private let paddingTop: CGFloat = 10.0
    private let paddingBottom: CGFloat = 10.0
    private let animationDuration: Double = 0.2
    private var barBackgroundColor: UIColor
    private var textViewBackgroundColor: UIColor
    private var textViewBorderColor: UIColor
        
    private var placeholderText: String?
    private var placeholderFont: UIFont
    private var placeholderTextColor: UIColor
    
    var plusButton: UIButton = UIButton()
    var voiceRecordingButton: UIButton = UIButton()
    var photoButton: UIButton = UIButton()
    var sendButton: UIButton = UIButton()
    
    var placeholderLabel: UILabel = UILabel()
    var textButtonContainer: UIView = UIView()
    var leftStackView: UIStackView = UIStackView()
    var rightStackView: UIStackView = UIStackView()

    var backgroundView: UIView = UIView()
    var shouldExpandTextViewToRight = true
    weak var delegate: ComposeViewDelegate?

    var composeTextView: ComposeTextView!

    private var isInputTextViewExpanded: Bool = false
    private var leftStackViewConstraint: NSLayoutConstraint!
    private var rightStackViewConstraint: NSLayoutConstraint!
    private var rightStackViewLeadingConstraint: NSLayoutConstraint!

    private var sendButtonBottomConstraint: NSLayoutConstraint!
    private var textContainerBottomAnchor: NSLayoutConstraint!
    private var windowAnchor: NSLayoutConstraint?

    private var backgroundViewBottomAnchor: NSLayoutConstraint!
    private var textViewMaxHeight: NSLayoutConstraint!
    
    init(uiConfiguration: SinchSDKConfig.UIConfig, localizatioConfiguration: SinchSDKConfig.LocalizationConfig) {
        barBackgroundColor = uiConfiguration.inputBarBackgroundColor
        textViewBackgroundColor = uiConfiguration.inputTextViewBackgroundColor
        textViewBorderColor = uiConfiguration.inputTextViewBorderColor
      
        placeholderTextColor = uiConfiguration.inputPlaceholderTextColor
        placeholderFont = UIFont.preferredFont(forTextStyle: .body)
        placeholderText  = localizatioConfiguration.inputPlaceholderText
        
        photoButton.setImage(uiConfiguration.photoImage, for: .normal)
        plusButton.setImage(uiConfiguration.plusImage, for: .normal)
        voiceRecordingButton.setImage(uiConfiguration.voiceRecordingImage, for: .normal)
        voiceRecordingButton.isHidden = true
        sendButton.setImage(uiConfiguration.sendImage, for: .normal)
        
        composeTextView = ComposeTextView(configuration: uiConfiguration)
        
        super.init()
    }
    
    override func setupSubviews() {
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = barBackgroundColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        addLeftContentButtons()
        addRightContentButtons()
        addTextViewAndSendButtonContainer()
        setupPlaceholderLabel()
       
    }
    
    override func setupConstraints() {
        
        leftStackViewConstraint = leftStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18)
        rightStackViewConstraint = rightStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -18)
        rightStackViewLeadingConstraint = rightStackView.leadingAnchor.constraint(equalTo: textButtonContainer.trailingAnchor, constant: 9)

        sendButtonBottomConstraint = sendButton.bottomAnchor.constraint(equalTo: textButtonContainer.bottomAnchor)
        backgroundViewBottomAnchor =  backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        textContainerBottomAnchor =  textButtonContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10)
        textViewMaxHeight = composeTextView.heightAnchor.constraint(equalToConstant: maxHeight - paddingTop - paddingBottom)
        NSLayoutConstraint.activate([
            
            leftStackViewConstraint,
            leftStackView.trailingAnchor.constraint(equalTo: textButtonContainer.leadingAnchor, constant: -9),
            leftStackView.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor, constant: 0),
            
            rightStackViewConstraint,
            rightStackViewLeadingConstraint,
            rightStackView.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor, constant: 0),
            
            plusButton.heightAnchor.constraint(equalToConstant: 40),
            plusButton.widthAnchor.constraint(equalToConstant: 38),
            
            photoButton.heightAnchor.constraint(equalToConstant: 40),
            photoButton.widthAnchor.constraint(equalToConstant: 38),
            
            voiceRecordingButton.heightAnchor.constraint(equalToConstant: 40),
            voiceRecordingButton.widthAnchor.constraint(equalToConstant: 38),
            
            backgroundView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            backgroundViewBottomAnchor,
            backgroundView.leftAnchor.constraint(equalTo: safeAreaLayoutGuide.leftAnchor),
            backgroundView.rightAnchor.constraint(equalTo: safeAreaLayoutGuide.rightAnchor),
            
            textButtonContainer.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 10),
            textContainerBottomAnchor,
            
            composeTextView.leadingAnchor.constraint(equalTo: textButtonContainer.leadingAnchor, constant: 10),
            composeTextView.trailingAnchor.constraint(equalTo: textButtonContainer.trailingAnchor, constant: -45),
            composeTextView.topAnchor.constraint(equalTo: textButtonContainer.topAnchor, constant: 0),
            composeTextView.bottomAnchor.constraint(equalTo: textButtonContainer.bottomAnchor, constant: 0),
            
            sendButton.trailingAnchor.constraint(equalTo: textButtonContainer.trailingAnchor, constant: -10),
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButtonBottomConstraint,
            
            placeholderLabel.leadingAnchor.constraint(equalTo: composeTextView.leadingAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(equalTo: composeTextView.trailingAnchor, constant: 0),
            placeholderLabel.topAnchor.constraint(equalTo: composeTextView.topAnchor, constant: 0),
            placeholderLabel.bottomAnchor.constraint(equalTo: composeTextView.bottomAnchor, constant: 0)
        ])
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window = window, window.safeAreaInsets.bottom > 0 else { return }
        windowAnchor?.isActive = false
        windowAnchor = textButtonContainer.bottomAnchor.constraint(lessThanOrEqualToSystemSpacingBelow: window.safeAreaLayoutGuide.bottomAnchor, multiplier: 1)
        windowAnchor?.constant = 0
        windowAnchor?.priority = UILayoutPriority(rawValue: 750)
        windowAnchor?.isActive = true
        backgroundViewBottomAnchor.constant = window.safeAreaInsets.bottom
    }

    override func resignFirstResponder() -> Bool {
        composeTextView.resignFirstResponder()
        return super.resignFirstResponder()
    }

    func setText(_ text: String) {
        composeTextView.text = text
        showHidePlaceholderAndSendButton(in: composeTextView)
    }

    // MARK: - Private
    
    private func setupPlaceholderLabel() {
        
        placeholderLabel.font = placeholderFont
        placeholderLabel.textColor = placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.numberOfLines = 1
        placeholderLabel.backgroundColor = .clear
        
        if let placeholderText = placeholderText {
            placeholderLabel.text = placeholderText
        }
        addSubview(placeholderLabel)
    }
    
    private func setupTextView() {
        composeTextView.delegate = self
        composeTextView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func addTextViewAndSendButtonContainer() {
        
        textButtonContainer.backgroundColor = textViewBackgroundColor
        textButtonContainer.layer.cornerRadius = 20.0
        textButtonContainer.layer.borderWidth = 1.0
        textButtonContainer.layer.borderColor = textViewBorderColor.cgColor
        textButtonContainer.clipsToBounds = true
        textButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        
        setupTextView()
        textButtonContainer.addSubview(composeTextView)
        
        setupSendButton()
        textButtonContainer.addSubview(sendButton)
        
        backgroundView.addSubview(textButtonContainer)
    }
    
    private func setupSendButton() {
        sendButton.imageEdgeInsets = UIEdgeInsets(top: 7.01, left: 5, bottom: 6.67, right: 5)
        sendButton.addTarget(self, action: #selector(sendMessage(_:)), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isHidden = true
    }
    
    private func addLeftContentButtons() {
        
        plusButton.imageEdgeInsets = UIEdgeInsets(top: 8, left: 7, bottom: 8, right: 7)
        plusButton.addTarget(self, action: #selector(plusButtonAction(_:)), for: .touchUpInside)
        
        leftStackView.addArrangedSubview(plusButton)
        leftStackView.distribution = .fill
        leftStackView.alignment = .center
        leftStackView.axis = .horizontal
        leftStackView.spacing = 2
        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        
        backgroundView.addSubview(leftStackView)
    }
    
    private func addRightContentButtons() {
        
        photoButton.imageEdgeInsets = UIEdgeInsets(top: 8, left: 7, bottom: 8, right: 7)
        voiceRecordingButton.imageEdgeInsets = UIEdgeInsets(top: 8, left: 7, bottom: 8, right: 7)
        voiceRecordingButton.addTarget(self, action: #selector(voiceRecordingAction(_:)), for: .touchUpInside)
        photoButton.addTarget(self, action: #selector(photoAction(_:)), for: .touchUpInside)
        
        rightStackView.addArrangedSubview(photoButton)
        rightStackView.addArrangedSubview(voiceRecordingButton)

        rightStackView.distribution = .fill
        rightStackView.alignment = .center
        rightStackView.axis = .horizontal
        rightStackView.spacing = 2
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        
        backgroundView.addSubview(rightStackView)
    }
    private func updateTextContainerCornerRadius(_ totalHeight: CGFloat) {
        
        if totalHeight < 60 {
            textButtonContainer.layer.cornerRadius = (totalHeight-20 )/2
        } else {
            textButtonContainer.layer.cornerRadius = 20.0
        }
    }
    
    private func updateButton(_ totalHeight: CGFloat) {
        
        guard let fontHeight = composeTextView.font?.lineHeight else { return }
        let numLines = Int((totalHeight - composeTextView.textContainerInset.top - composeTextView.textContainerInset.bottom) / fontHeight)
        let imageHeight: CGFloat = 16.32
        let topImageInset: CGFloat = 7.01
        let bottomImageInset: CGFloat = 6.67
        
        if numLines == 1 {
            let totalInset = totalHeight - imageHeight - topImageInset - bottomImageInset
            sendButtonBottomConstraint.constant = -abs(totalInset)/2
        }
    }
    
    override var intrinsicContentSize: CGSize {
        let size = composeTextView.sizeThatFits(CGSize(width: composeTextView.frame.width, height: CGFloat(MAXFLOAT)))
        let totalHeight = size.height + paddingTop + paddingBottom
        if totalHeight <= maxHeight {
            updateTextContainerCornerRadius(totalHeight)
            updateButton(size.height)
            textViewMaxHeight.isActive = false
            composeTextView.isScrollEnabled = false
            
            composeTextView.invalidateIntrinsicContentSize()
            
            return CGSize(width: self.bounds.width, height: totalHeight)
            
        } else {
            composeTextView.isScrollEnabled = true
            textViewMaxHeight.isActive = true
            
            return CGSize(width: self.bounds.width, height: maxHeight)
        }
    }
    
    @objc private func photoAction(_ sender: UIButton) {
        
        delegate?.choosePhoto()
        
    }
    @objc private func plusButtonAction(_ sender: UIButton) {
        delegate?.chooseAction()

    }
    @objc private func voiceRecordingAction(_ sender: UIButton) {
        
    }
    @objc private func sendMessage(_ sender: UIButton) {
        
        guard let text = composeTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return
        }
        composeTextView.text = nil
        delegate?.sendMessage(text: text)
        updateUI(composeTextView)
    }
    private func expandTextView() {
        if !isInputTextViewExpanded {
            
            isInputTextViewExpanded = true
            rightStackViewConstraint?.constant = rightStackView.frame.width
            rightStackViewLeadingConstraint?.constant = 25
            UIView.animate(withDuration: animationDuration, animations: {
                self.layoutIfNeeded()
                
            })
        }
    }
    
    private func collapseTextView() {
        
        if isInputTextViewExpanded {
            isInputTextViewExpanded = false
            rightStackViewConstraint?.constant = -18
            rightStackViewLeadingConstraint?.constant = 9

            UIView.animate(withDuration: animationDuration) {
                
                self.layoutIfNeeded()
            }
        }
    }
    private func updateUI(_ textView: UITextView) {
        updateTextViewConstraints()
        
        if shouldExpandTextViewToRight {
            if textView.text.isEmpty {
                
                collapseTextView()
            } else {
                
                expandTextView()
            }
        }
        showHidePlaceholderAndSendButton(in: textView)
    }
    
    private func showHidePlaceholderAndSendButton(in textView: UITextView) {
        if !textView.hasText || textView.text.isEmpty {
            
            placeholderLabel.isHidden = false
            sendButton.isHidden = true
        } else {
            
            placeholderLabel.isHidden = true
            sendButton.isHidden = false
        }
    }
    
    private func updateTextViewConstraints() {
        invalidateIntrinsicContentSize()
        updateConstraints()
    }
}

extension ComposeView: UITextViewDelegate {
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        
        textView.selectedRange = NSRange(location: textView.text.count, length: 0)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        
        updateUI(textView)
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        
        true
    }
    
    func textViewDidChange(_ textView: UITextView) {
        
        updateUI(textView)
    }
}
