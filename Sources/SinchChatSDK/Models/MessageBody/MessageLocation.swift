struct MessageLocation: MessageBody {
    
    var label: String
    var title: String
    var latitude: Double
    var longitude: Double
    var sendDate: Int64?
    var isExpanded: Bool = false

    func getReadMore(maxCount: Int, textToAdd: String ) -> String {
        
        if title.count > maxCount && !isExpanded {
           
            return title.prefix(maxCount) + "... " + "\(textToAdd)"
            
        }
        
        return title
      
    }
}
