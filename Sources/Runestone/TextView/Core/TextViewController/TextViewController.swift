import Combine
import Foundation

final class TextViewController {
    var textView: TextView {
        get {
            if let textView = _textView {
                return textView
            } else {
                fatalError("Text view has been deallocated or has not been assigned")
            }
        }
        set {
            _textView = newValue
        }
    }
    private weak var _textView: TextView?
    var selectedRange: NSRange? {
        didSet {
            if selectedRange != oldValue {
                layoutManager.selectedRange = selectedRange
                layoutManager.setNeedsLayoutLineSelection()
                textView.setNeedsLayout()
            }
        }
    }
    var markedRange: NSRange?
    var isEditing = false {
        didSet {
            if isEditing != oldValue {
                layoutManager.isEditing = isEditing
            }
        }
    }
    var isEditable = true {
        didSet {
            if isEditable != oldValue && !isEditable && isEditing {
                textView.resignFirstResponder()
                isEditing = false
                textView.editorDelegate?.textViewDidEndEditing(textView)
            }
        }
    }
    var isSelectable = true {
        didSet {
            if isSelectable != oldValue {
                textView.isUserInteractionEnabled = isSelectable
                if !isSelectable && isEditing {
                    textView.resignFirstResponder()
                    selectedRange = nil
                    #if os(iOS)
                    textView.handleTextSelectionChange()
                    #endif
                    isEditing = false
                    textView.editorDelegate?.textViewDidEndEditing(textView)
                }
            }
        }
    }
    var viewport: CGRect {
        get {
            return layoutManager.viewport
        }
        set {
            if newValue != layoutManager.viewport {
                layoutManager.viewport = newValue
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var text: String {
        get {
            return stringView.string as String
        }
        set {
            let nsString = newValue as NSString
            if nsString != stringView.string {
                stringView.string = nsString
                languageMode.parse(nsString)
                lineManager.rebuild()
                if let oldSelectedRange = selectedRange {
                    #if os(iOS)
                    textView.inputDelegate?.selectionWillChange(textView)
                    #endif
                    selectedRange = safeSelectionRange(from: oldSelectedRange)
                    #if os(iOS)
                    textView.inputDelegate?.selectionDidChange(textView)
                    #endif
                }
                contentSizeService.invalidateContentSize()
                gutterWidthService.invalidateLineNumberWidth()
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
                if !preserveUndoStackWhenSettingString {
                    timedUndoManager.removeAllActions()
                }
            }
        }
    }
    var hasPendingContentSizeUpdate = false
    var scrollViewWidth: CGFloat = 0 {
        didSet {
            if scrollViewWidth != oldValue {
                contentSizeService.scrollViewWidth = scrollViewWidth
                layoutManager.scrollViewWidth = scrollViewWidth
                if isLineWrappingEnabled {
                    invalidateLines()
                }
            }
        }
    }
    var safeAreaInsets: MultiPlatformEdgeInsets = .zero {
        didSet {
            if safeAreaInsets != oldValue {
                layoutManager.safeAreaInsets = safeAreaInsets
            }
        }
    }

    private(set) var stringView = StringView() {
        didSet {
            if stringView !== oldValue {
                caretRectService.stringView = stringView
                lineManager.stringView = stringView
                lineControllerFactory.stringView = stringView
                lineControllerStorage.stringView = stringView
                layoutManager.stringView = stringView
                indentController.stringView = stringView
                lineMovementController.stringView = stringView
            }
        }
    }
    let invisibleCharacterConfiguration = InvisibleCharacterConfiguration()
    private(set) var lineManager: LineManager {
        didSet {
            if lineManager !== oldValue {
                indentController.lineManager = lineManager
                lineMovementController.lineManager = lineManager
                gutterWidthService.lineManager = lineManager
                contentSizeService.lineManager = lineManager
                caretRectService.lineManager = lineManager
                selectionRectService.lineManager = lineManager
                highlightService.lineManager = lineManager
            }
        }
    }
    let highlightService: HighlightService
    let lineControllerFactory: LineControllerFactory
    let lineControllerStorage: LineControllerStorage
    let gutterWidthService: GutterWidthService
    let contentSizeService: ContentSizeService
    let caretRectService: CaretRectService
    let selectionRectService: SelectionRectService
    let layoutManager: LayoutManager
    let indentController: IndentController
    let lineMovementController: LineMovementController
    let pageGuideController = PageGuideController()
    let highlightNavigationController = HighlightNavigationController()
    let timedUndoManager = TimedUndoManager()
    
    var languageMode: InternalLanguageMode = PlainTextInternalLanguageMode() {
        didSet {
            if languageMode !== oldValue {
                indentController.languageMode = languageMode
                if let treeSitterLanguageMode = languageMode as? TreeSitterInternalLanguageMode {
                    treeSitterLanguageMode.delegate = self
                }
            }
        }
    }
    var lineEndings: LineEnding = .lf
    var theme: Theme = DefaultTheme() {
        didSet {
            applyThemeToChildren()
        }
    }
    var characterPairs: [CharacterPair] = [] {
        didSet {
            maximumLeadingCharacterPairComponentLength = characterPairs.map(\.leading.utf16.count).max() ?? 0
        }
    }
    var characterPairTrailingComponentDeletionMode: CharacterPairTrailingComponentDeletionMode = .disabled
    var showLineNumbers = false {
        didSet {
            if showLineNumbers != oldValue {
                #if os(iOS)
                textView.inputDelegate?.selectionWillChange(textView)
                #endif
                caretRectService.showLineNumbers = showLineNumbers
                gutterWidthService.showLineNumbers = showLineNumbers
                layoutManager.showLineNumbers = showLineNumbers
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
                #if os(iOS)
                textView.inputDelegate?.selectionDidChange(textView)
                #endif
            }
        }
    }
    var lineSelectionDisplayType: LineSelectionDisplayType {
        get {
            return layoutManager.lineSelectionDisplayType
        }
        set {
            layoutManager.lineSelectionDisplayType = newValue
        }
    }
    var showTabs: Bool {
        get {
            return invisibleCharacterConfiguration.showTabs
        }
        set {
            if newValue != invisibleCharacterConfiguration.showTabs {
                invisibleCharacterConfiguration.showTabs = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showSpaces: Bool {
        get {
            return invisibleCharacterConfiguration.showSpaces
        }
        set {
            if newValue != invisibleCharacterConfiguration.showSpaces {
                invisibleCharacterConfiguration.showSpaces = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showNonBreakingSpaces: Bool {
        get {
            return invisibleCharacterConfiguration.showNonBreakingSpaces
        }
        set {
            if newValue != invisibleCharacterConfiguration.showNonBreakingSpaces {
                invisibleCharacterConfiguration.showNonBreakingSpaces = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showLineBreaks: Bool {
        get {
            return invisibleCharacterConfiguration.showLineBreaks
        }
        set {
            if newValue != invisibleCharacterConfiguration.showLineBreaks {
                invisibleCharacterConfiguration.showLineBreaks = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.setNeedsDisplayOnLines()
                textView.setNeedsLayout()
            }
        }
    }
    var showSoftLineBreaks: Bool {
        get {
            return invisibleCharacterConfiguration.showSoftLineBreaks
        }
        set {
            if newValue != invisibleCharacterConfiguration.showSoftLineBreaks {
                invisibleCharacterConfiguration.showSoftLineBreaks = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.setNeedsDisplayOnLines()
                textView.setNeedsLayout()
            }
        }
    }
    var tabSymbol: String {
        get {
            return invisibleCharacterConfiguration.tabSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.tabSymbol {
                invisibleCharacterConfiguration.tabSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var spaceSymbol: String {
        get {
            return invisibleCharacterConfiguration.spaceSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.spaceSymbol {
                invisibleCharacterConfiguration.spaceSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var nonBreakingSpaceSymbol: String {
        get {
            return invisibleCharacterConfiguration.nonBreakingSpaceSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.nonBreakingSpaceSymbol {
                invisibleCharacterConfiguration.nonBreakingSpaceSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var lineBreakSymbol: String {
        get {
            return invisibleCharacterConfiguration.lineBreakSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.lineBreakSymbol {
                invisibleCharacterConfiguration.lineBreakSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var softLineBreakSymbol: String {
        get {
            return invisibleCharacterConfiguration.softLineBreakSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.softLineBreakSymbol {
                invisibleCharacterConfiguration.softLineBreakSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var indentStrategy: IndentStrategy = .tab(length: 2) {
        didSet {
            if indentStrategy != oldValue {
                indentController.indentStrategy = indentStrategy
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
                textView.layoutIfNeeded()
            }
        }
    }
    var gutterLeadingPadding: CGFloat = 3 {
        didSet {
            if gutterLeadingPadding != oldValue {
                gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var gutterTrailingPadding: CGFloat = 3 {
        didSet {
            if gutterTrailingPadding != oldValue {
                gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var gutterMinimumCharacterCount: Int = 1 {
        didSet {
            if gutterMinimumCharacterCount != oldValue {
                gutterWidthService.gutterMinimumCharacterCount = gutterMinimumCharacterCount
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var textContainerInset: MultiPlatformEdgeInsets {
        get {
            return layoutManager.textContainerInset
        }
        set {
            if newValue != layoutManager.textContainerInset {
                caretRectService.textContainerInset = newValue
                selectionRectService.textContainerInset = newValue
                contentSizeService.textContainerInset = newValue
                layoutManager.textContainerInset = newValue
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var isLineWrappingEnabled: Bool {
        get {
            return layoutManager.isLineWrappingEnabled
        }
        set {
            if newValue != layoutManager.isLineWrappingEnabled {
                contentSizeService.isLineWrappingEnabled = newValue
                layoutManager.isLineWrappingEnabled = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
            }
        }
    }
    var lineBreakMode: LineBreakMode = .byWordWrapping {
        didSet {
            if lineBreakMode != oldValue {
                invalidateLines()
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
            }
        }
    }
    var gutterWidth: CGFloat {
        gutterWidthService.gutterWidth
    }
    var lineHeightMultiplier: CGFloat = 1 {
        didSet {
            if lineHeightMultiplier != oldValue {
                selectionRectService.lineHeightMultiplier = lineHeightMultiplier
                layoutManager.lineHeightMultiplier = lineHeightMultiplier
                invalidateLines()
                lineManager.estimatedLineHeight = estimatedLineHeight
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var kern: CGFloat = 0 {
        didSet {
            if kern != oldValue {
                invalidateLines()
                pageGuideController.kern = kern
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                textView.setNeedsLayout()
            }
        }
    }
    var showPageGuide = false {
        didSet {
            if showPageGuide != oldValue {
                if showPageGuide {
                    textView.addSubview(pageGuideController.guideView)
                    textView.sendSubviewToBack(pageGuideController.guideView)
                    textView.setNeedsLayout()
                } else {
                    pageGuideController.guideView.removeFromSuperview()
                    textView.setNeedsLayout()
                }
            }
        }
    }
    var pageGuideColumn: Int {
        get {
            return pageGuideController.column
        }
        set {
            if newValue != pageGuideController.column {
                pageGuideController.column = newValue
                textView.setNeedsLayout()
            }
        }
    }
    var verticalOverscrollFactor: CGFloat = 0 {
        didSet {
            if verticalOverscrollFactor != oldValue {
                invalidateContentSizeIfNeeded()
            }
        }
    }
    var horizontalOverscrollFactor: CGFloat = 0 {
        didSet {
            if horizontalOverscrollFactor != oldValue {
                invalidateContentSizeIfNeeded()
            }
        }
    }
    var lengthOfInitallyLongestLine: Int? {
        lineManager.initialLongestLine?.data.totalLength
    }
    var highlightedRanges: [HighlightedRange] {
        get {
            return highlightService.highlightedRanges
        }
        set {
            if newValue != highlightService.highlightedRanges {
                highlightService.highlightedRanges = newValue
                layoutManager.setNeedsLayout()
                layoutManager.layoutIfNeeded()
                highlightNavigationController.highlightedRanges = newValue
            }
        }
    }
    var highlightedRangeLoopingMode: HighlightedRangeLoopingMode {
        get {
            if highlightNavigationController.loopRanges {
                return .enabled
            } else {
                return .disabled
            }
        }
        set {
            switch newValue {
            case .enabled:
                highlightNavigationController.loopRanges = true
            case .disabled:
                highlightNavigationController.loopRanges = false
            }
        }
    }
    var isAutomaticScrollEnabled = false
    var hasPendingFullLayout = false
    private(set) var maximumLeadingCharacterPairComponentLength = 0

    private var estimatedLineHeight: CGFloat {
        theme.font.totalLineHeight * lineHeightMultiplier
    }
    private var preserveUndoStackWhenSettingString = false
    private var cancellables: Set<AnyCancellable> = []

    init(textView: TextView) {
        _textView = textView
        lineManager = LineManager(stringView: stringView)
        highlightService = HighlightService(lineManager: lineManager)
        lineControllerFactory = LineControllerFactory(
            stringView: stringView,
            highlightService: highlightService,
            invisibleCharacterConfiguration: invisibleCharacterConfiguration
        )
        lineControllerStorage = LineControllerStorage(
            stringView: stringView,
            lineControllerFactory: lineControllerFactory
        )
        gutterWidthService = GutterWidthService(lineManager: lineManager)
        contentSizeService = ContentSizeService(
            lineManager: lineManager,
            lineControllerStorage: lineControllerStorage,
            gutterWidthService: gutterWidthService,
            invisibleCharacterConfiguration: invisibleCharacterConfiguration
        )
        caretRectService = CaretRectService(
            stringView: stringView,
            lineManager: lineManager,
            lineControllerStorage: lineControllerStorage,
            gutterWidthService: gutterWidthService
        )
        selectionRectService = SelectionRectService(
            lineManager: lineManager,
            contentSizeService: contentSizeService,
            gutterWidthService: gutterWidthService,
            caretRectService: caretRectService
        )
        layoutManager = LayoutManager(
            lineManager: lineManager,
            languageMode: languageMode,
            stringView: stringView,
            lineControllerStorage: lineControllerStorage,
            contentSizeService: contentSizeService,
            gutterWidthService: gutterWidthService,
            caretRectService: caretRectService,
            selectionRectService: selectionRectService,
            highlightService: highlightService,
            invisibleCharacterConfiguration: invisibleCharacterConfiguration
        )
        indentController = IndentController(
            stringView: stringView,
            lineManager: lineManager,
            languageMode: languageMode,
            indentStrategy: indentStrategy,
            indentFont: theme.font
        )
        lineMovementController = LineMovementController(
            lineManager: lineManager,
            stringView: stringView,
            lineControllerStorage: lineControllerStorage
        )
        layoutManager.delegate = self
        layoutManager.containerView = textView
        applyThemeToChildren()
        indentController.delegate = self
        lineControllerStorage.delegate = self
        gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
        gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
        setupContentSizeObserver()
        setupGutterWidthObserver()
    }

    func setState(_ state: TextViewState, addUndoAction: Bool = false) {
        let oldText = stringView.string
        let newText = state.stringView.string
        stringView = state.stringView
        theme = state.theme
        languageMode = state.languageMode
        lineControllerStorage.removeAllLineControllers()
        lineManager = state.lineManager
        lineManager.estimatedLineHeight = estimatedLineHeight
        layoutManager.languageMode = state.languageMode
        layoutManager.lineManager = state.lineManager
        contentSizeService.invalidateContentSize()
        gutterWidthService.invalidateLineNumberWidth()
        if addUndoAction {
            if newText != oldText {
                let newRange = NSRange(location: 0, length: newText.length)
                timedUndoManager.endUndoGrouping()
                timedUndoManager.beginUndoGrouping()
                addUndoOperation(replacing: newRange, withText: oldText as String)
                timedUndoManager.endUndoGrouping()
            }
        } else {
            timedUndoManager.removeAllActions()
        }
        if let oldSelectedRange = selectedRange {
            #if os(iOS)
            textView.inputDelegate?.selectionWillChange(textView)
            selectedRange = safeSelectionRange(from: oldSelectedRange)
            textView.inputDelegate?.selectionDidChange(textView)
            #endif
        }
        if textView.window != nil {
            performFullLayout()
        } else {
            hasPendingFullLayout = true
        }
    }

    func setLanguageMode(_ languageMode: LanguageMode, completion: ((Bool) -> Void)? = nil) {
        let internalLanguageMode = InternalLanguageModeFactory.internalLanguageMode(
            from: languageMode,
            stringView: stringView,
            lineManager: lineManager
        )
        self.languageMode = internalLanguageMode
        layoutManager.languageMode = internalLanguageMode
        internalLanguageMode.parse(stringView.string) { [weak self] finished in
            if let self = self, finished {
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                self.layoutManager.layoutIfNeeded()
            }
            completion?(finished)
        }
    }

    func highlightedRange(for range: NSRange) -> HighlightedRange? {
        highlightedRanges.first(where: { $0.range == selectedRange })
    }
}

private extension TextViewController {
    private func applyThemeToChildren() {
        gutterWidthService.font = theme.lineNumberFont
        lineManager.estimatedLineHeight = estimatedLineHeight
        indentController.indentFont = theme.font
        pageGuideController.font = theme.font
        pageGuideController.guideView.hairlineWidth = theme.pageGuideHairlineWidth
        pageGuideController.guideView.hairlineColor = theme.pageGuideHairlineColor
        pageGuideController.guideView.backgroundColor = theme.pageGuideBackgroundColor
        layoutManager.theme = theme
    }

    private func setupContentSizeObserver() {
        contentSizeService.$isContentSizeInvalid.filter { $0 }.sink { [weak self] _ in
            if self?._textView != nil {
                self?.invalidateContentSizeIfNeeded()
            }
        }.store(in: &cancellables)
    }

    private func setupGutterWidthObserver() {
        gutterWidthService.didUpdateGutterWidth.sink { [weak self] in
            if let self = self, let textView = self._textView {
                // Typeset lines again when the line number width changes since changing line number width may increase or reduce the number of line fragments in a line.
                textView.setNeedsLayout()
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                textView.editorDelegate?.textViewDidChangeGutterWidth(self.textView)
            }
        }.store(in: &cancellables)
    }
}

// MARK: - TreeSitterLanguageModeDelegate
extension TextViewController: TreeSitterLanguageModeDelegate {
    func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult? {
        guard byteIndex.value >= 0 && byteIndex < stringView.string.byteCount else {
            return nil
        }
        let targetByteCount: ByteCount = 4 * 1_024
        let endByte = min(byteIndex + targetByteCount, stringView.string.byteCount)
        let byteRange = ByteRange(from: byteIndex, to: endByte)
        if let result = stringView.bytes(in: byteRange) {
            return TreeSitterTextProviderResult(bytes: result.bytes, length: UInt32(result.length.value))
        } else {
            return nil
        }
    }
}

// MARK: - LayoutManagerDelegate
extension TextViewController: LayoutManagerDelegate {
    func layoutManager(_ layoutManager: LayoutManager, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint) {
        let isScrolling = textView.isDragging || textView.isDecelerating
        if contentOffsetAdjustment != .zero && isScrolling {
            textView.contentOffset = CGPoint(
                x: textView.contentOffset.x + contentOffsetAdjustment.x,
                y: textView.contentOffset.y + contentOffsetAdjustment.y
            )
        }
    }
}

// MARK: - LineControllerStorageDelegate
extension TextViewController: LineControllerStorageDelegate {
    func lineControllerStorage(_ storage: LineControllerStorage, didCreate lineController: LineController) {
        lineController.delegate = self
        lineController.constrainingWidth = layoutManager.constrainingLineWidth
        lineController.estimatedLineFragmentHeight = theme.font.totalLineHeight
        lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
        lineController.tabWidth = indentController.tabWidth
        lineController.theme = theme
        lineController.lineBreakMode = lineBreakMode
    }
}

// MARK: - LineControllerDelegate
extension TextViewController: LineControllerDelegate {
    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter? {
        let syntaxHighlighter = languageMode.createLineSyntaxHighlighter()
        syntaxHighlighter.kern = kern
        return syntaxHighlighter
    }

    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController) {
        textView.setNeedsLayout()
        layoutManager.setNeedsLayout()
    }
}

// MARK: - IndentControllerDelegate
extension TextViewController: IndentControllerDelegate {
    func indentController(_ controller: IndentController, shouldInsert text: String, in range: NSRange) {
        replaceText(in: range, with: text)
    }

    func indentController(_ controller: IndentController, shouldSelect range: NSRange) {
        #if os(iOS)
        textView.inputDelegate?.selectionWillChange(textView)
        selectedRange = range
        textView.inputDelegate?.selectionDidChange(textView)
        #else
        selectedRange = range
        #endif
    }

    func indentControllerDidUpdateTabWidth(_ controller: IndentController) {
        invalidateLines()
    }
}