// Style: the app's own buttons and segmented pickers, drawn as front-panel parts in the chosen face (Faces.swift)
// instead of macOS's blue accent controls. A button is a key; a tinted one carries an LED in its colour; the one
// primary action (Apply) is the aluminium key with the lit orange slot. A picker is a recessed track with the
// chosen item a raised key.

import SwiftUI

struct PillButtonStyle: ButtonStyle {
    var tint: Color? = nil          // nil = plain key; a colour = an LED of that colour on the key
    var compact = false
    var primary = false
    var lit = true                  // false: the LED is there but dark (what it stands for isn't running)
    var sentence = false            // the words as written ("Switch…"), smaller, instead of spaced capitals

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, tint: tint, compact: compact, primary: primary, lit: lit, sentence: sentence)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let tint: Color?
        let compact: Bool
        let primary: Bool
        let lit: Bool
        let sentence: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            KeyLook(kind: primary ? .primary : .plain, pressed: configuration.isPressed,
                    height: compact ? 22 : 26, radius: compact ? 3 : 4, hPad: compact ? 9 : 12) {
                HStack(spacing: 6) {
                    // a key that can't be pressed shows its LED dark and grey, no glow (a lit one read as "ready", only paler)
                    if let tint, !primary { LED(color: tint, lit: enabled && lit) }
                    // the key's own capitals and spacing are set outside; the label's own settings win
                    if sentence { configuration.label.textCase(nil).tracking(0).font(.system(size: 11.5, weight: .semibold)) }
                    else { configuration.label }
                }
            }
            .brightness(hover && enabled ? 0.03 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ tint: Color, compact: Bool = false, lit: Bool = true) -> PillButtonStyle {
        PillButtonStyle(tint: tint, compact: compact, lit: lit)
    }
    /// The one primary action on a page (Apply).
    static func primaryKey(compact: Bool = false) -> PillButtonStyle { PillButtonStyle(compact: compact, primary: true) }
    /// The settings window's keys: short words as written, compact. `next`: the one clear next step (the primary key).
    static func sentenceKey(next: Bool = false) -> PillButtonStyle { PillButtonStyle(compact: true, primary: next, sentence: true) }
}

/// A choice of a few words (the shortcut, the model, thinking): the words as written on a recessed track, the chosen one
/// a raised key. Each choice is an action, so a choice can do something other than select (Other… records a key).
struct KeySegments: View {
    struct Choice: Identifiable { let id: String; let title: String }
    let choices: [Choice]
    let selected: String?
    let pick: (String) -> Void
    @Environment(\.face) private var face
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices) { c in
                let on = c.id == selected
                Button { pick(c.id) } label: {
                    Text(c.title)
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
                        .foregroundStyle(on ? face.legend : face.trackLegend)
                        .shadow(color: on ? face.legendShadow : .clear, radius: 0, y: face.legendShadowY)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background { if on { RaisedShape(finish: face.key, radius: 3) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(WellShape(well: face.track, radius: 5))
        .opacity(enabled ? 1 : 0.5)
        .fixedSize()
        .alignmentGuide(.rowLine) { d in d[VerticalAlignment.center] }
    }
}

/// A text field in a recessed well. Offscreen pictures (`--render-settings`) can't draw macOS's field, so they get its
/// text or placeholder printed in the same well.
struct SField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var onCommit: () -> Void = {}
    @Environment(\.face) private var face
    /// Set while a picture of the settings is drawn.
    static var drawing = false

    var body: some View {
        Group {
            if Self.drawing {
                Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? face.muted : face.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text, onCommit: onCommit).textFieldStyle(.plain)
            }
        }
        .font(.system(size: size, weight: weight))
        .padding(.horizontal, 7).frame(height: size + 13)
        .frame(width: width)
        .background(WellShape(well: face.win, radius: 4))
    }
}

/// A segmented picker: printed choices on a recessed track, the chosen one a raised key.
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var compact = false
    var fill = false            // stretch the choices across the width
    let title: (Value) -> String
    @Environment(\.face) private var face

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button { selection = o } label: {
                    Text(title(o))
                        .font(.system(size: compact ? 9 : 9.5, weight: .semibold)).tracking(1).textCase(.uppercase)
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? face.legend : face.trackLegend)
                        .shadow(color: on ? face.legendShadow : .clear, radius: 0, y: face.legendShadowY)
                        .padding(.horizontal, fill ? 6 : compact ? 8 : 10)      // stretched choices share any extra width
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: compact ? 20 : 22)
                        .background { if on { RaisedShape(finish: face.key, radius: 3) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(WellShape(well: face.track, radius: 5))
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

/// The quick chat's spacing (diagrams/cl-quick-chat-design.html in the design notes): one outer gap that the header's
/// name, the answers and the field box all keep from the window's edges, and rows on a 4 pt grid.
enum QCSpace {
    /// The window's edge to the field box (left, right, bottom), to the header's name and to the answers.
    static let gap: CGFloat = 10
    /// The window's corners, and the bar's (the bar is the field box on its own).
    static let corner: CGFloat = 20
    /// The field box inside the window: its corners and its padding (the field text and the controls start 12 in).
    static let boxCorner: CGFloat = 12
    static let boxPadding = EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12)
    static let barPadding = EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
    /// The header's height; its content is centred in it.
    static let header: CGFloat = 40
    /// A control (profile, model, thinking), Send, Stop and the header's buttons.
    static let row: CGFloat = 28
    /// A control's padding at either side; its text sits on the box's own padding, the hover fill reaches past it.
    static let keyPadding: CGFloat = 8
    static let keyCorner: CGFloat = 7
    /// The small buttons: an answer's Copy and Ask again, a code block's Copy.
    static let small: CGFloat = 24
}
