//
//  MessageEditingViewControllers.swift
//  UniLLMs
//
//  Hosts message edit and revision history presentation controllers.
//

import UIKit

final class MessageEditViewController: UIViewController, UITextViewDelegate {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let topInset: CGFloat = 16.0
        static let bottomInset: CGFloat = 16.0
        static let textInset: CGFloat = 12.0
        static let cornerRadius: CGFloat = 14.0
        static let minimumTextHeight: CGFloat = 180.0
    }

    private let initialText: String
    private let allowsEmptyText: Bool
    private let textView = UITextView()
    private var sendButtonItem: UIBarButtonItem?

    var onSubmit: ((String) -> Void)?

    init(text: String, allowsEmptyText: Bool) {
        initialText = text
        self.allowsEmptyText = allowsEmptyText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialText = ""
        allowsEmptyText = false
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()
        configureTextView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textView.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendAvailability()
    }

    private func configureNavigationItem() {
        title = String(localized: .chatEditMessage)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonPressed)
        )
        let sendItem = UIBarButtonItem(
            title: String(localized: .generalSend),
            style: .prominent,
            target: self,
            action: #selector(sendButtonPressed)
        )
        navigationItem.rightBarButtonItem = sendItem
        sendButtonItem = sendItem
        updateSendAvailability()
    }

    private func configureTextView() {
        view.backgroundColor = .clear

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .secondarySystemBackground
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.text = initialText
        textView.textContainerInset = UIEdgeInsets(
            top: Metrics.textInset,
            left: Metrics.textInset,
            bottom: Metrics.textInset,
            right: Metrics.textInset
        )
        textView.textContainer.lineFragmentPadding = 0.0
        textView.layer.cornerRadius = Metrics.cornerRadius
        textView.layer.cornerCurve = .continuous
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Metrics.topInset
            ),
            textView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            textView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            textView.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -Metrics.bottomInset
            ),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumTextHeight)
        ])
        updateSendAvailability()
    }

    private func updateSendAvailability() {
        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendButtonItem?.isEnabled = allowsEmptyText || !trimmedText.isEmpty
    }

    @objc private func cancelButtonPressed() {
        dismiss(animated: true)
    }

    @objc private func sendButtonPressed() {
        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsEmptyText || !trimmedText.isEmpty else {
            return
        }

        onSubmit?(trimmedText)
    }
}

final class MessageRevisionHistoryViewController: UITableViewController {
    private enum ReuseIdentifier {
        static let revisionCell = "MessageRevisionHistoryCell"
    }

    private let items: [ChatMessageRevisionHistoryItem]
    var onSelectRevision: ((ChatMessageRevision) -> Void)?

    init(revisions: [ChatMessageRevision]) {
        items = ChatMessageRevisionHistoryItem.items(from: revisions)
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        items = []
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: .generalHistory)
        view.backgroundColor = .clear
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonPressed)
        )
        tableView.register(MessageRevisionHistoryCell.self, forCellReuseIdentifier: ReuseIdentifier.revisionCell)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReuseIdentifier.revisionCell,
            for: indexPath
        )
        (cell as? MessageRevisionHistoryCell)?.configure(with: item)
        cell.accessoryType = .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectRevision?(items[indexPath.row].revision)
    }

    @objc private func doneButtonPressed() {
        dismiss(animated: true)
    }
}

private final class MessageRevisionHistoryCell: UITableViewCell {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16.0
        static let verticalInset: CGFloat = 10.0
        static let rowSpacing: CGFloat = 4.0
        static let subtitleSpacing: CGFloat = 8.0
        static let tagCornerRadius: CGFloat = 7.0
    }

    private let titleLabel = UILabel()
    private let subtitleStackView = UIStackView()
    private let dateLabel = UILabel()
    private let countTagLabel = MessageRevisionCountTagLabel()
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        titleLabel.text = nil
        dateLabel.text = nil
        countTagLabel.text = nil
        countTagLabel.isHidden = true
    }

    func configure(with item: ChatMessageRevisionHistoryItem) {
        titleLabel.text = item.title
        dateLabel.text = item.subtitle

        let followUpCount = item.followUpUserMessageCount
        countTagLabel.text = "+\(followUpCount)"
        countTagLabel.isHidden = followUpCount == 0
    }

    private func configure() {
        selectionStyle = .default

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel
        dateLabel.numberOfLines = 1
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countTagLabel.font = .preferredFont(forTextStyle: .caption1)
        countTagLabel.adjustsFontForContentSizeCategory = true
        countTagLabel.textColor = .secondaryLabel
        countTagLabel.textAlignment = .center
        countTagLabel.backgroundColor = .tertiarySystemFill
        countTagLabel.layer.cornerRadius = Metrics.tagCornerRadius
        countTagLabel.layer.cornerCurve = .continuous
        countTagLabel.clipsToBounds = true
        countTagLabel.numberOfLines = 1
        countTagLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countTagLabel.setContentHuggingPriority(.required, for: .horizontal)

        subtitleStackView.axis = .horizontal
        subtitleStackView.alignment = .center
        subtitleStackView.spacing = Metrics.subtitleSpacing
        subtitleStackView.translatesAutoresizingMaskIntoConstraints = false
        subtitleStackView.addArrangedSubview(dateLabel)
        subtitleStackView.addArrangedSubview(countTagLabel)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Metrics.rowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleStackView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Metrics.verticalInset
            ),
            stackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Metrics.horizontalInset
            ),
            stackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Metrics.horizontalInset
            ),
            stackView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Metrics.verticalInset
            )
        ])
    }
}

private final class MessageRevisionCountTagLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 2.0, left: 7.0, bottom: 2.0, right: 7.0)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingSize = super.sizeThatFits(
            CGSize(
                width: max(0.0, size.width - textInsets.left - textInsets.right),
                height: max(0.0, size.height - textInsets.top - textInsets.bottom)
            )
        )
        return CGSize(
            width: fittingSize.width + textInsets.left + textInsets.right,
            height: fittingSize.height + textInsets.top + textInsets.bottom
        )
    }
}
