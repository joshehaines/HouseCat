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
