import Foundation
import SwiftData

/// A ~500 character slice of an invoice's raw text with its on-device sentence embedding.
@Model
final class InvoiceChunk {
    var index: Int
    var text: String
    var embedding: [Double]
    var expense: Expense?

    init(index: Int, text: String, embedding: [Double], expense: Expense) {
        self.index = index
        self.text = text
        self.embedding = embedding
        self.expense = expense
    }
}
