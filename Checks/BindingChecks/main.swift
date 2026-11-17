import SwiftUI

final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

func binding<Value>(to box: Box<Value>) -> Binding<Value> {
    Binding(get: { box.value }, set: { box.value = $0 })
}

for deletedIndex in 0..<3 {
    let box = Box([
        BulletItem(text: "первый"),
        BulletItem(text: "второй"),
        BulletItem(text: "третий")
    ])
    let originalIDs = box.value.map(\.id)
    let originalTexts = box.value.map(\.text)
    let collection = binding(to: box)
    let oldBindings = box.value.map { StableBindings.element(for: $0, in: collection).text }

    box.value.remove(at: deletedIndex)
    precondition(oldBindings[deletedIndex].wrappedValue == originalTexts[deletedIndex])
    oldBindings[deletedIndex].wrappedValue = "не должно вернуться"
    precondition(box.value.count == 2)

    for originalIndex in 0..<3 where originalIndex != deletedIndex {
        oldBindings[originalIndex].wrappedValue = "обновлено \(originalIndex)"
        precondition(
            box.value.first(where: { $0.id == originalIDs[originalIndex] })?.text
                == "обновлено \(originalIndex)"
        )
    }
}

let firstBlock = NoteBlock.text("первый")
let secondBlock = NoteBlock.text("второй")
let blocks = Box([firstBlock, secondBlock])
let firstBlockBinding = StableBindings.element(for: firstBlock, in: binding(to: blocks))
blocks.value.swapAt(0, 1)
precondition(firstBlockBinding.wrappedValue.text == "первый")
var changedBlock = firstBlockBinding.wrappedValue
changedBlock.text = "после переноса"
firstBlockBinding.wrappedValue = changedBlock
precondition(blocks.value[1].text == "после переноса")
blocks.value.removeLast()
precondition(firstBlockBinding.wrappedValue.text == "первый")
firstBlockBinding.wrappedValue = changedBlock
precondition(blocks.value.count == 1)

let table = Box([["заголовок", "столбец"], ["строка", "ячейка"]])
let cell = StableBindings.cell(row: 1, column: 1, fallback: "ячейка", in: binding(to: table))
table.value[1].removeLast()
precondition(cell.wrappedValue == "ячейка")
cell.wrappedValue = "не должно вернуться"
precondition(table.value[1] == ["строка"])
table.value.removeLast()
precondition(cell.wrappedValue == "ячейка")
cell.wrappedValue = "не должно вернуться"
precondition(table.value.count == 1)

print("Проверки привязок пройдены: пункты списка, блоки и таблица")
