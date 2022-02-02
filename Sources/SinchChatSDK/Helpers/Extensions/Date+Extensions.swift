import Foundation

extension Date {
    
    func getFormattedTime() -> String {
        
        let dateFormat = DateFormatter()
        dateFormat.dateFormat = "HH:mm"
        
        return dateFormat.string(from: self)
    }
    
    func getFormattedDate() -> String {
        
        if Calendar.current.isDateInToday(self) {
            return  NSLocalizedString("label_today", bundle: Bundle.staticBundle, comment: "")
        } else if Calendar.current.isDateInYesterday(self) {
            return  NSLocalizedString("label_yesterday", bundle: Bundle.staticBundle, comment: "")

        } else {

            return  DateFormatter.localizedString(from: self, dateStyle: .medium, timeStyle: .none)
        }
    }
}
