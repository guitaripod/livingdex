import UIKit

/// Attribution for the third-party photos, data and code Living Dex shows or links.
final class CreditsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Entry {
        let title: String
        let detail: String
        let url: URL?
    }
    private struct Section {
        let header: String
        let footer: String?
        let entries: [Entry]
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let sections: [Section] = [
        Section(
            header: "Sample photos",
            footer: "Dedicated to the public domain (CC0) by their photographers.",
            entries: [
                .init(title: "European Robin", detail: "sudenkorentoko · iNaturalist", url: URL(string: "https://www.inaturalist.org/observations/203563707")),
                .init(title: "Red Fox", detail: "terrybb · iNaturalist", url: URL(string: "https://www.inaturalist.org/observations/327531235")),
                .init(title: "Fly Agaric", detail: "sigridjakob · iNaturalist", url: URL(string: "https://www.inaturalist.org/observations/97332092")),
                .init(title: "Wood Anemone", detail: "robphippen · iNaturalist", url: URL(string: "https://www.inaturalist.org/observations/203339532")),
            ]),
        Section(
            header: "Data",
            footer: "Each species call shows its own recordist and license where it plays.",
            entries: [
                .init(title: "GBIF", detail: "Taxonomy, occurrence records, conservation status", url: URL(string: "https://www.gbif.org")),
                .init(title: "Wikipedia", detail: "Species summaries, CC BY-SA", url: URL(string: "https://www.wikipedia.org")),
                .init(title: "Wikimedia Commons", detail: "Animal calls, with attribution", url: URL(string: "https://commons.wikimedia.org")),
                .init(title: "Xeno-canto", detail: "Bird and animal sound recordings, with attribution", url: URL(string: "https://xeno-canto.org")),
            ]),
        Section(
            header: "Open source",
            footer: nil,
            entries: [
                .init(title: "GRDB.swift", detail: "Gwendal Roué · MIT", url: URL(string: "https://github.com/groue/GRDB.swift")),
            ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Credits"
        view.backgroundColor = .systemGroupedBackground
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].entries.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = sections[indexPath.section].entries[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = entry.title
        content.secondaryText = entry.detail
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = entry.url == nil ? .none : .disclosureIndicator
        cell.selectionStyle = entry.url == nil ? .none : .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let url = sections[indexPath.section].entries[indexPath.row].url else { return }
        UIApplication.shared.open(url)
    }
}
