/// Shop rules that are not prices (StoreKit owns prices).
public enum ShopRules {
    /// Seasonal stock (an outfit with months, such as the pumpkin hat) is on sale
    /// only in its months and comes back every year (Josh, 18 Oct 2026). The shop
    /// may say when it is on sale until; it never counts down or says "last chance".
    public static func isOnSale(months: [Int], on day: GameDay) -> Bool {
        months.isEmpty || months.contains(day.month)
    }

    /// The last day it is on sale this time round ("On sale until 31 October"),
    /// or nil if it is not seasonal or not on sale today.
    public static func lastSaleDay(months: [Int], from day: GameDay) -> GameDay? {
        guard !months.isEmpty, months.contains(day.month), Set(months).count < 12 else { return nil }
        var last = day
        while months.contains(last.advanced(by: 1).month) {
            last = last.advanced(by: 1)
        }
        return last
    }
}

/// The Bean catalogue (SPEC "Home and furniture", "Economy"): the pieces bought with Beans, shown in the
/// decorate tray for the room you are in. Each shows its price; a piece above your level shows the level.
public enum BeanShop {
    public enum Status: Equatable, Sendable {
        case buyable(price: Int)
        case needsBeans(price: Int)
        case needsLevel(Int)
    }

    /// A room's Bean pieces, cheapest first (the room's own, then the rest of the catalogue's).
    /// Every piece sold for Beans: the Bean catalogue, and the room looks' pieces one at a time (one currency).
    public static func stock(for room: RoomID, catalogue: CatalogueFile) -> [CatalogueFile.Item] {
        let beanItems = catalogue.items.filter { ($0.pool == .beans && $0.beans != nil) || $0.pool == .set }
        let price = { (item: CatalogueFile.Item) in BeanPrices.piece(item) }
        let own = beanItems.filter { $0.room == room.rawValue }.sorted { (price($0), $0.id) < (price($1), $1.id) }
        let rest = beanItems.filter { $0.room != room.rawValue }.sorted { ($0.room, price($0), $0.id) < ($1.room, price($1), $1.id) }
        return own + rest
    }

    public static func status(of item: CatalogueFile.Item, level: Int, beans: Int) -> Status {
        let price = BeanPrices.piece(item)
        if level < item.level {
            return .needsLevel(item.level)
        }
        return beans >= price ? .buyable(price: price) : .needsBeans(price: price)
    }
}
