import Foundation

extension Date {
    
    func getFormattedTime() -> String {
        
        let dateFormat = DateFormatter()
        dateFormat.dateFormat = "HH:mm"
        
        return dateFormat.string(from: self)
    }
    
    func getFormattedDate(localizationConfiguration: SinchSDKConfig.LocalizationConfig) -> String {
        
        if Calendar.current.isDateInToday(self) {
            return  localizationConfiguration.today
        } else if Calendar.current.isDateInYesterday(self) {
            return  localizationConfiguration.yesterday

        } else {

            return  DateFormatter.localizedString(from: self, dateStyle: .medium, timeStyle: .none)
        }
    }
}
