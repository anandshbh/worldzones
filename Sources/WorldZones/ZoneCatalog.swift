import Foundation

struct ZoneCandidate: Identifiable, Hashable {
    let name: String
    let detail: String
    let identifier: String
    var id: String { name + "|" + identifier }
}

enum ZoneCatalog {
    /// Well-known cities that don't have their own tz database identifier.
    private static let aliases: [(String, String, String)] = [
        ("San Francisco", "United States", "America/Los_Angeles"),
        ("Seattle", "United States", "America/Los_Angeles"),
        ("San Diego", "United States", "America/Los_Angeles"),
        ("Las Vegas", "United States", "America/Los_Angeles"),
        ("Portland", "United States", "America/Los_Angeles"),
        ("Austin", "United States", "America/Chicago"),
        ("Dallas", "United States", "America/Chicago"),
        ("Houston", "United States", "America/Chicago"),
        ("Atlanta", "United States", "America/New_York"),
        ("Boston", "United States", "America/New_York"),
        ("Miami", "United States", "America/New_York"),
        ("Washington, D.C.", "United States", "America/New_York"),
        ("Philadelphia", "United States", "America/New_York"),
        ("Salt Lake City", "United States", "America/Denver"),
        ("Montreal", "Canada", "America/Toronto"),
        ("Ottawa", "Canada", "America/Toronto"),
        ("Rio de Janeiro", "Brazil", "America/Sao_Paulo"),
        ("Barcelona", "Spain", "Europe/Madrid"),
        ("Munich", "Germany", "Europe/Berlin"),
        ("Frankfurt", "Germany", "Europe/Berlin"),
        ("Hamburg", "Germany", "Europe/Berlin"),
        ("Milan", "Italy", "Europe/Rome"),
        ("Geneva", "Switzerland", "Europe/Zurich"),
        ("Edinburgh", "United Kingdom", "Europe/London"),
        ("Manchester", "United Kingdom", "Europe/London"),
        ("Tel Aviv", "Israel", "Asia/Jerusalem"),
        ("Abu Dhabi", "United Arab Emirates", "Asia/Dubai"),
        ("Bengaluru", "India", "Asia/Kolkata"),
        ("Bangalore", "India", "Asia/Kolkata"),
        ("Mumbai", "India", "Asia/Kolkata"),
        ("New Delhi", "India", "Asia/Kolkata"),
        ("Hyderabad", "India", "Asia/Kolkata"),
        ("Chennai", "India", "Asia/Kolkata"),
        ("Pune", "India", "Asia/Kolkata"),
        ("Beijing", "China", "Asia/Shanghai"),
        ("Shenzhen", "China", "Asia/Shanghai"),
        ("Osaka", "Japan", "Asia/Tokyo"),
        ("Hanoi", "Vietnam", "Asia/Ho_Chi_Minh"),
        ("Canberra", "Australia", "Australia/Sydney"),
        ("Wellington", "New Zealand", "Pacific/Auckland"),
        // United States & Canada
        ("San Jose", "United States", "America/Los_Angeles"),
        ("Sacramento", "United States", "America/Los_Angeles"),
        ("Minneapolis", "United States", "America/Chicago"),
        ("Nashville", "United States", "America/Chicago"),
        ("New Orleans", "United States", "America/Chicago"),
        ("Orlando", "United States", "America/New_York"),
        ("Charlotte", "United States", "America/New_York"),
        ("Raleigh", "United States", "America/New_York"),
        ("Pittsburgh", "United States", "America/New_York"),
        ("Baltimore", "United States", "America/New_York"),
        ("Calgary", "Canada", "America/Edmonton"),
        ("Quebec City", "Canada", "America/Toronto"),
        // Latin America
        ("Guadalajara", "Mexico", "America/Mexico_City"),
        ("Brasília", "Brazil", "America/Sao_Paulo"),
        ("Medellín", "Colombia", "America/Bogota"),
        // Europe
        ("Rennes", "France", "Europe/Paris"),
        ("Lyon", "France", "Europe/Paris"),
        ("Marseille", "France", "Europe/Paris"),
        ("Nice", "France", "Europe/Paris"),
        ("Toulouse", "France", "Europe/Paris"),
        ("Bordeaux", "France", "Europe/Paris"),
        ("Nantes", "France", "Europe/Paris"),
        ("Strasbourg", "France", "Europe/Paris"),
        ("Seville", "Spain", "Europe/Madrid"),
        ("Valencia", "Spain", "Europe/Madrid"),
        ("Porto", "Portugal", "Europe/Lisbon"),
        ("Florence", "Italy", "Europe/Rome"),
        ("Venice", "Italy", "Europe/Rome"),
        ("Naples", "Italy", "Europe/Rome"),
        ("Turin", "Italy", "Europe/Rome"),
        ("Cologne", "Germany", "Europe/Berlin"),
        ("Stuttgart", "Germany", "Europe/Berlin"),
        ("Düsseldorf", "Germany", "Europe/Berlin"),
        ("Rotterdam", "Netherlands", "Europe/Amsterdam"),
        ("The Hague", "Netherlands", "Europe/Amsterdam"),
        ("Antwerp", "Belgium", "Europe/Brussels"),
        ("Kraków", "Poland", "Europe/Warsaw"),
        ("Birmingham", "United Kingdom", "Europe/London"),
        ("Glasgow", "United Kingdom", "Europe/London"),
        ("Liverpool", "United Kingdom", "Europe/London"),
        ("Cork", "Ireland", "Europe/Dublin"),
        ("Saint Petersburg", "Russia", "Europe/Moscow"),
        ("Gothenburg", "Sweden", "Europe/Stockholm"),
        ("Basel", "Switzerland", "Europe/Zurich"),
        ("Salzburg", "Austria", "Europe/Vienna"),
        // Middle East & Africa
        ("Doha", "Qatar", "Asia/Qatar"),
        ("Jeddah", "Saudi Arabia", "Asia/Riyadh"),
        ("Ankara", "Turkey", "Europe/Istanbul"),
        ("Marrakesh", "Morocco", "Africa/Casablanca"),
        ("Cape Town", "South Africa", "Africa/Johannesburg"),
        ("Abuja", "Nigeria", "Africa/Lagos"),
        // Asia & Oceania
        ("Ahmedabad", "India", "Asia/Kolkata"),
        ("Jaipur", "India", "Asia/Kolkata"),
        ("Gurugram", "India", "Asia/Kolkata"),
        ("Noida", "India", "Asia/Kolkata"),
        ("Islamabad", "Pakistan", "Asia/Karachi"),
        ("Lahore", "Pakistan", "Asia/Karachi"),
        ("Guangzhou", "China", "Asia/Shanghai"),
        ("Hangzhou", "China", "Asia/Shanghai"),
        ("Chengdu", "China", "Asia/Shanghai"),
        ("Kyoto", "Japan", "Asia/Tokyo"),
        ("Yokohama", "Japan", "Asia/Tokyo"),
        ("Busan", "South Korea", "Asia/Seoul"),
        ("Bali", "Indonesia", "Asia/Makassar"),
        ("Phuket", "Thailand", "Asia/Bangkok"),
        ("Cebu", "Philippines", "Asia/Manila"),
        ("Gold Coast", "Australia", "Australia/Brisbane"),
        ("Christchurch", "New Zealand", "Pacific/Auckland"),
        ("UTC", "Coordinated Universal Time", "UTC"),
    ]

    /// The world's major cities by region, for the "All Cities" browser.
    static let majorCities: [(region: String, cities: [ZoneCandidate])] = [
        ("North America", [
            ("Honolulu", "Pacific/Honolulu"), ("Anchorage", "America/Anchorage"), ("Vancouver", "America/Vancouver"),
            ("Seattle", "America/Los_Angeles"), ("San Francisco", "America/Los_Angeles"), ("Los Angeles", "America/Los_Angeles"),
            ("Las Vegas", "America/Los_Angeles"), ("Phoenix", "America/Phoenix"), ("Denver", "America/Denver"),
            ("Mexico City", "America/Mexico_City"), ("Dallas", "America/Chicago"), ("Houston", "America/Chicago"),
            ("Chicago", "America/Chicago"), ("Toronto", "America/Toronto"), ("Montreal", "America/Toronto"),
            ("Atlanta", "America/New_York"), ("Miami", "America/New_York"), ("Washington, D.C.", "America/New_York"),
            ("New York", "America/New_York"), ("Boston", "America/New_York"), ("Havana", "America/Havana"),
        ]),
        ("South America", [
            ("Bogota", "America/Bogota"), ("Lima", "America/Lima"), ("Caracas", "America/Caracas"),
            ("Santiago", "America/Santiago"), ("Buenos Aires", "America/Argentina/Buenos_Aires"),
            ("Sao Paulo", "America/Sao_Paulo"), ("Rio de Janeiro", "America/Sao_Paulo"),
        ]),
        ("Europe", [
            ("Reykjavik", "Atlantic/Reykjavik"), ("Lisbon", "Europe/Lisbon"), ("Dublin", "Europe/Dublin"),
            ("London", "Europe/London"), ("Edinburgh", "Europe/London"), ("Madrid", "Europe/Madrid"),
            ("Barcelona", "Europe/Madrid"), ("Paris", "Europe/Paris"), ("Rennes", "Europe/Paris"),
            ("Brussels", "Europe/Brussels"), ("Amsterdam", "Europe/Amsterdam"), ("Zurich", "Europe/Zurich"),
            ("Geneva", "Europe/Zurich"), ("Milan", "Europe/Rome"), ("Rome", "Europe/Rome"),
            ("Berlin", "Europe/Berlin"), ("Munich", "Europe/Berlin"), ("Frankfurt", "Europe/Berlin"),
            ("Copenhagen", "Europe/Copenhagen"), ("Oslo", "Europe/Oslo"), ("Stockholm", "Europe/Stockholm"),
            ("Helsinki", "Europe/Helsinki"), ("Vienna", "Europe/Vienna"), ("Prague", "Europe/Prague"),
            ("Warsaw", "Europe/Warsaw"), ("Budapest", "Europe/Budapest"), ("Athens", "Europe/Athens"),
            ("Kyiv", "Europe/Kyiv"), ("Istanbul", "Europe/Istanbul"), ("Moscow", "Europe/Moscow"),
        ]),
        ("Africa", [
            ("Casablanca", "Africa/Casablanca"), ("Accra", "Africa/Accra"), ("Lagos", "Africa/Lagos"),
            ("Kinshasa", "Africa/Kinshasa"), ("Cairo", "Africa/Cairo"), ("Addis Ababa", "Africa/Addis_Ababa"),
            ("Nairobi", "Africa/Nairobi"), ("Johannesburg", "Africa/Johannesburg"), ("Cape Town", "Africa/Johannesburg"),
        ]),
        ("Middle East", [
            ("Tel Aviv", "Asia/Jerusalem"), ("Riyadh", "Asia/Riyadh"), ("Doha", "Asia/Qatar"),
            ("Tehran", "Asia/Tehran"), ("Dubai", "Asia/Dubai"), ("Abu Dhabi", "Asia/Dubai"),
        ]),
        ("Asia", [
            ("Karachi", "Asia/Karachi"), ("Mumbai", "Asia/Kolkata"), ("New Delhi", "Asia/Kolkata"),
            ("Bengaluru", "Asia/Kolkata"), ("Kathmandu", "Asia/Kathmandu"), ("Dhaka", "Asia/Dhaka"),
            ("Bangkok", "Asia/Bangkok"), ("Hanoi", "Asia/Ho_Chi_Minh"), ("Ho Chi Minh", "Asia/Ho_Chi_Minh"),
            ("Kuala Lumpur", "Asia/Kuala_Lumpur"), ("Singapore", "Asia/Singapore"), ("Jakarta", "Asia/Jakarta"),
            ("Manila", "Asia/Manila"), ("Hong Kong", "Asia/Hong_Kong"), ("Shanghai", "Asia/Shanghai"),
            ("Beijing", "Asia/Shanghai"), ("Taipei", "Asia/Taipei"), ("Seoul", "Asia/Seoul"),
            ("Tokyo", "Asia/Tokyo"), ("Osaka", "Asia/Tokyo"),
        ]),
        ("Oceania", [
            ("Perth", "Australia/Perth"), ("Adelaide", "Australia/Adelaide"), ("Brisbane", "Australia/Brisbane"),
            ("Sydney", "Australia/Sydney"), ("Melbourne", "Australia/Melbourne"), ("Auckland", "Pacific/Auckland"),
        ]),
    ].map { region, cities in
        (region, cities.map { ZoneCandidate(name: $0.0, detail: countryName(for: $0.1) ?? region, identifier: $0.1) })
    }

    /// Localized country name for a zone, e.g. "France" for Europe/Paris.
    static func countryName(for identifier: String) -> String? {
        countryCodes[identifier].flatMap { Locale.current.localizedString(forRegionCode: $0) }
    }

    private static let featured: Set<String> = [
        "San Francisco", "Seattle", "Chicago", "New York", "Toronto", "Sao Paulo",
        "London", "Paris", "Rennes", "Berlin", "Dubai", "Bengaluru",
        "Singapore", "Hong Kong", "Shanghai", "Tokyo", "Sydney", "UTC",
    ]

    static let all: [ZoneCandidate] = {
        var seen = Set<String>()
        var result: [ZoneCandidate] = []
        let fromAliases = aliases.map { ZoneCandidate(name: $0.0, detail: $0.1, identifier: $0.2) }
        let fromDatabase = TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .map { id -> ZoneCandidate in
                let region = id.split(separator: "/").first.map(String.init) ?? ""
                return ZoneCandidate(name: cityName(for: id), detail: region, identifier: id)
            }
        for c in fromAliases + fromDatabase where seen.insert(c.id.lowercased()).inserted {
            result.append(c)
        }
        return result.sorted { $0.name < $1.name }
    }()

    /// Search keys folded once up front, so typing doesn't re-fold ~500 strings per keystroke.
    private static let index: [(candidate: ZoneCandidate, name: String, rest: String)] = all.map {
        ($0, fold($0.name), fold($0.detail) + "|" + fold($0.identifier))
    }

    private static let popular = all.filter { featured.contains($0.name) }

    /// Time zone identifier → ISO country code, from the system tz database.
    private static let countryCodes: [String: String] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let cols = line.split(separator: "\t")
            if cols.count >= 3 { map[String(cols[2])] = String(cols[0]) }
        }
        return map
    }()

    /// Flag emoji for the country a zone belongs to, e.g. "🇫🇷" for Europe/Paris; nil for UTC and the like.
    static func flag(for identifier: String) -> String? {
        guard let code = countryCodes[identifier] else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
        return String(String.UnicodeScalarView(scalars))
    }

    static func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func search(_ query: String) -> [ZoneCandidate] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return popular }

        var prefix: [ZoneCandidate] = [], contains: [ZoneCandidate] = []
        for entry in index {
            if entry.name.hasPrefix(q) {
                prefix.append(entry.candidate)
            } else if entry.name.contains(q) || entry.rest.contains(q) {
                contains.append(entry.candidate)
            }
        }

        // Abbreviations like "PST" or "CET" resolve to a representative zone.
        var abbreviated: [ZoneCandidate] = []
        let upper = query.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.count <= 5, let id = TimeZone.abbreviationDictionary[upper] {
            abbreviated.append(ZoneCandidate(name: cityName(for: id), detail: "\(upper) · \(id)", identifier: id))
        }
        return Array((abbreviated + prefix + contains).prefix(60))
    }
}
