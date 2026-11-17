import SwiftUI

enum StableBindings {
    static func element<Element: Identifiable>(
        for element: Element,
        in collection: Binding<[Element]>
    ) -> Binding<Element> where Element.ID: Equatable {
        Binding(
            get: {
                collection.wrappedValue.first(where: { $0.id == element.id }) ?? element
            },
            set: { updated in
                var values = collection.wrappedValue
                guard let index = values.firstIndex(where: { $0.id == element.id }) else { return }
                values[index] = updated
                collection.wrappedValue = values
            }
        )
    }

    static func cell(
        row: Int,
        column: Int,
        fallback: String,
        in table: Binding<[[String]]>
    ) -> Binding<String> {
        Binding(
            get: {
                let rows = table.wrappedValue
                guard rows.indices.contains(row), rows[row].indices.contains(column) else {
                    return fallback
                }
                return rows[row][column]
            },
            set: { updated in
                var rows = table.wrappedValue
                guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
                rows[row][column] = updated
                table.wrappedValue = rows
            }
        )
    }
}
