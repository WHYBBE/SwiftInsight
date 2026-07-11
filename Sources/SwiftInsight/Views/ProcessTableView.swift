import SwiftUI
import AppKit

/// AppKit NSTableView 封装：系统级条纹、流畅滚动，且数据更新不走 SwiftUI.Table 重入路径
struct ProcessTableView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Binding var selectedPID: Int32?

    var body: some View {
        VStack(spacing: 0) {
            sortHeader
            ProcessNSTable(
                processes: monitor.displayedProcesses,
                selectedPID: $selectedPID,
                onTerminate: { pid, force in
                    monitor.terminate(pid: pid, force: force)
                },
                onFilterCategory: { category in
                    monitor.categoryFilter = category
                }
            )
        }
    }

    private var sortHeader: some View {
        HStack(spacing: 12) {
            Text("排序:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SortColumn.allCases) { col in
                Button {
                    monitor.toggleSort(col)
                } label: {
                    HStack(spacing: 2) {
                        Text(col.displayName)
                            .font(.caption.weight(monitor.sortColumn == col ? .semibold : .regular))
                        if monitor.sortColumn == col {
                            Image(systemName: monitor.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        monitor.sortColumn == col
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(monitor.displayedProcesses.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - NSTableView bridge

private struct ProcessNSTable: NSViewRepresentable {
    let processes: [MonitoredProcess]
    @Binding var selectedPID: Int32?
    var onTerminate: (Int32, Bool) -> Void
    var onFilterCategory: (ProcessCategory) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.gridStyleMask = []
        table.headerView = NSTableHeaderView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.menu = context.coordinator.makeContextMenu()

        for col in Coordinator.columns {
            let column = NSTableColumn(identifier: col.id)
            column.title = col.title
            column.width = col.width
            column.minWidth = col.minWidth
            column.resizingMask = .userResizingMask
            if col.numeric {
                column.headerCell.alignment = .right
            }
            table.addTableColumn(column)
        }

        scrollView.documentView = table
        context.coordinator.tableView = table
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(processes: processes, selectedPID: selectedPID)
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        struct ColumnDef {
            let id: NSUserInterfaceItemIdentifier
            let title: String
            let width: CGFloat
            let minWidth: CGFloat
            let numeric: Bool
        }

        static let columns: [ColumnDef] = [
            .init(id: .init("name"), title: "名称", width: 320, minWidth: 180, numeric: false),
            .init(id: .init("cpu"), title: "CPU %", width: 72, minWidth: 56, numeric: true),
            .init(id: .init("memory"), title: "内存", width: 90, minWidth: 70, numeric: true),
            .init(id: .init("threads"), title: "线程", width: 56, minWidth: 44, numeric: true),
            .init(id: .init("pid"), title: "PID", width: 64, minWidth: 48, numeric: true),
            .init(id: .init("user"), title: "用户", width: 88, minWidth: 60, numeric: false),
        ]

        var parent: ProcessNSTable
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        private var rows: [MonitoredProcess] = []
        private var isApplying = false
        private var iconCache: [String: NSImage] = [:]

        init(_ parent: ProcessNSTable) {
            self.parent = parent
        }

        func apply(processes: [MonitoredProcess], selectedPID: Int32?) {
            guard !isApplying else { return }

            let dataChanged = !Self.sameDisplayData(rows, processes)
            let selectionChanged = selectedPID != currentSelectedPID()

            guard dataChanged || selectionChanged else { return }

            isApplying = true
            // 避开 NSTableView 委托回调栈内同步 reload
            DispatchQueue.main.async { [weak self] in
                guard let self, let table = self.tableView else {
                    self?.isApplying = false
                    return
                }

                let savedSelection = selectedPID
                let clip = self.scrollView?.contentView
                let savedOrigin = clip?.bounds.origin

                if dataChanged {
                    self.rows = processes
                    table.reloadData()
                }

                if let pid = savedSelection,
                   let index = self.rows.firstIndex(where: { $0.pid == pid }) {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                } else if savedSelection == nil {
                    table.deselectAll(nil)
                }

                if let clip, let savedOrigin {
                    clip.scroll(to: savedOrigin)
                    self.scrollView?.reflectScrolledClipView(clip)
                }

                self.isApplying = false
            }
        }

        private func currentSelectedPID() -> Int32? {
            guard let table = tableView, table.selectedRow >= 0, table.selectedRow < rows.count else {
                return nil
            }
            return rows[table.selectedRow].pid
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < rows.count, let tableColumn else { return nil }
            let process = rows[row]
            let id = tableColumn.identifier

            switch id.rawValue {
            case "name":
                return nameCell(tableView: tableView, process: process)
            case "cpu":
                return textCell(
                    tableView: tableView,
                    id: id,
                    text: process.cpuFormatted,
                    alignment: .right,
                    color: cpuColor(process.cpuPercent)
                )
            case "memory":
                return textCell(
                    tableView: tableView,
                    id: id,
                    text: process.memoryFormatted,
                    alignment: .right,
                    color: .labelColor
                )
            case "threads":
                return textCell(
                    tableView: tableView,
                    id: id,
                    text: "\(process.threadCount)",
                    alignment: .right,
                    color: .secondaryLabelColor
                )
            case "pid":
                return textCell(
                    tableView: tableView,
                    id: id,
                    text: "\(process.pid)",
                    alignment: .right,
                    color: .secondaryLabelColor
                )
            case "user":
                return textCell(
                    tableView: tableView,
                    id: id,
                    text: process.username,
                    alignment: .left,
                    color: .secondaryLabelColor
                )
            default:
                return nil
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplying, let table = tableView else { return }
            let pid: Int32?
            if table.selectedRow >= 0, table.selectedRow < rows.count {
                pid = rows[table.selectedRow].pid
            } else {
                pid = nil
            }
            if parent.selectedPID != pid {
                parent.selectedPID = pid
            }
        }

        @objc func doubleClicked(_ sender: Any?) {
            // 预留：双击可扩展为显示详情
        }

        // MARK: Cells

        private func nameCell(tableView: NSTableView, process: MonitoredProcess) -> NSView {
            let cellID = NSUserInterfaceItemIdentifier("nameCell")
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
                ?? makeIconTextCell(identifier: cellID)

            cell.imageView?.image = icon(for: process)
            cell.imageView?.imageScaling = .scaleProportionallyUpOrDown

            let title = process.name
            let tag = process.category.shortName
            let attributed = NSMutableAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            attributed.append(NSAttributedString(
                string: "  \(tag)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
            cell.textField?.attributedStringValue = attributed
            cell.textField?.toolTip = process.path.isEmpty ? process.name : process.path
            cell.textField?.lineBreakMode = .byTruncatingTail
            return cell
        }

        private func textCell(
            tableView: NSTableView,
            id: NSUserInterfaceItemIdentifier,
            text: String,
            alignment: NSTextAlignment,
            color: NSColor
        ) -> NSView {
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
                ?? makeTextCell(identifier: id)
            cell.textField?.stringValue = text
            cell.textField?.alignment = alignment
            cell.textField?.textColor = color
            cell.textField?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            cell.textField?.lineBreakMode = .byTruncatingTail
            return cell
        }

        private func makeIconTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isBordered = false
            textField.drawsBackground = false
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.imageView = imageView
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isBordered = false
            textField.drawsBackground = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func icon(for process: MonitoredProcess) -> NSImage {
            let key = process.path.isEmpty ? process.name : process.path
            if let cached = iconCache[key] { return cached }
            let image = ProcessClassifier.icon(for: process.path, name: process.name)
            image.size = NSSize(width: 16, height: 16)
            iconCache[key] = image
            if iconCache.count > 512 {
                iconCache.removeAll(keepingCapacity: true)
            }
            return image
        }

        private func cpuColor(_ cpu: Double) -> NSColor {
            if cpu >= 50 { return .systemRed }
            if cpu >= 20 { return .systemOrange }
            if cpu >= 5 { return .labelColor }
            return .secondaryLabelColor
        }

        private static func sameDisplayData(_ a: [MonitoredProcess], _ b: [MonitoredProcess]) -> Bool {
            guard a.count == b.count else { return false }
            for i in a.indices {
                let x = a[i]
                let y = b[i]
                if x.pid != y.pid
                    || x.name != y.name
                    || abs(x.cpuPercent - y.cpuPercent) > 0.05
                    || x.memoryBytes != y.memoryBytes
                    || x.threadCount != y.threadCount
                    || x.username != y.username
                    || x.category != y.category {
                    return false
                }
            }
            return true
        }

        // MARK: Context menu

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            return menu
        }

        private func processAtClickedRow() -> MonitoredProcess? {
            guard let table = tableView else { return nil }
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard row >= 0, row < rows.count else { return nil }
            return rows[row]
        }
    }
}

extension ProcessNSTable.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let process = processAtClickedRow() else { return }

        let quit = NSMenuItem(title: "退出", action: #selector(quitProcess(_:)), keyEquivalent: "")
        quit.target = self
        quit.representedObject = process.pid
        menu.addItem(quit)

        let force = NSMenuItem(title: "强制退出", action: #selector(forceQuitProcess(_:)), keyEquivalent: "")
        force.target = self
        force.representedObject = process.pid
        menu.addItem(force)

        menu.addItem(.separator())

        if !process.path.isEmpty {
            let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealInFinder(_:)), keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = process.path
            menu.addItem(reveal)

            let copyPath = NSMenuItem(title: "复制路径", action: #selector(copyString(_:)), keyEquivalent: "")
            copyPath.target = self
            copyPath.representedObject = process.path
            menu.addItem(copyPath)
        }

        if let bid = process.bundleIdentifier {
            let copyBID = NSMenuItem(title: "复制 Bundle ID", action: #selector(copyString(_:)), keyEquivalent: "")
            copyBID.target = self
            copyBID.representedObject = bid
            menu.addItem(copyBID)
        }

        menu.addItem(.separator())

        let filter = NSMenuItem(title: "筛选此分类", action: #selector(filterCategory(_:)), keyEquivalent: "")
        filter.target = self
        filter.representedObject = process.category.rawValue
        menu.addItem(filter)
    }

    @objc private func quitProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        parent.onTerminate(pid, false)
    }

    @objc private func forceQuitProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        parent.onTerminate(pid, true)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func copyString(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    @objc private func filterCategory(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let category = ProcessCategory(rawValue: raw) else { return }
        parent.onFilterCategory(category)
    }
}
