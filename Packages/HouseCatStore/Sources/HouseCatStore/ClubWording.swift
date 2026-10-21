/// The words beside Cat Club's plans (App Review 3.1.2: the price that will be charged is the clearest thing on the
/// page; a free trial is named only to a player StoreKit says may take one, `ProductInfo.trialDays`, since a lapsed or
/// current subscriber gets none and must not be promised one). Every string here is tested with a fake eligibility.
public enum ClubWording {
    /// Under the buy button: what is charged and when, then how it renews.
    public static func terms(yearly: Bool, yearPrice: String?, monthPrice: String?, trialDays: Int?) -> String {
        let year = yearPrice ?? "…", month = monthPrice ?? "…"
        let plan = yearly
            ? trialDays.map { "\($0) days free, then \(year) a year." } ?? "\(year) a year, from today."
            : "\(month) a month, from today."
        return plan + " Renews automatically until you cancel, at least a day before it renews, in Settings."
    }

    /// The plan card's second line: the yearly one's trial (when there is one) and its price a month, the monthly
    /// one's billing.
    public static func planLine(yearly: Bool, perMonth: String?, trialDays: Int?) -> String {
        guard yearly else { return "Billed every month" }
        let month = perMonth.map { "\($0) a month" }
        if let trialDays {
            return "\(trialDays) days free" + (month.map { " · \($0)" } ?? "")
        }
        return month.map { "Billed yearly · \($0)" } ?? "Billed every year"
    }

    /// The offer card's line for Cat Club: the trial then the yearly price, or the yearly price alone.
    public static func offerLine(yearPrice: String, trialDays: Int?) -> String {
        trialDays.map { "\($0) days free, then \(yearPrice) a year" } ?? "\(yearPrice) a year"
    }
}
