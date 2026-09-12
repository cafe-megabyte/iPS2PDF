# iPS2PDF Project Instructions

## Source organization

- A Swift source file must declare at most one top-level type. This includes classes, structures, enumerations, actors, protocols, and type aliases.
- Put a generally reusable type in its own file named after that type. Nest a type inside its owning type when it is only an implementation detail.
- Extensions may stay with the type they extend or live in a focused extension file; they must not be used to hide unrelated top-level types in one file.

## Localized text

- All static user-facing text must use compile-time-discoverable localization APIs so Xcode can maintain `Localizable.xcstrings` automatically.
- In SwiftUI, put string literals directly in localization-aware initializers and modifiers such as `Text("Settings")`, `Button("Apply")`, `Label("Remove", systemImage: "trash")`, `.navigationTitle("Joboptions")`, and `.accessibilityLabel("Edit selected Joboptions")`.
- When a reusable SwiftUI helper must receive localizable copy, accept `LocalizedStringResource` and construct it explicitly at the call site, for example `LocalizedStringResource("Open PDF…")`. Do not pass static user-facing copy through `String` or through a custom `LocalizedStringKey` parameter, because Xcode may not discover that indirection reliably.
- In non-SwiftUI Swift code that requires a localized `String`, use `String(localized: "Conversion failed")` rather than a raw string or a dynamically constructed localization key.
- Use `Text(verbatim:)` and raw dynamic strings only for content that must not be localized, such as product names, filenames, identifiers, imported document content, and runtime diagnostics.
- Do not keep obsolete catalog entries. If no source still uses a localized string, remove the stale entry instead of marking it manual merely to silence extraction warnings.

## Joboptions consistency belongs to the consistency engine

- Never disable, lock, hide, or otherwise prevent editing a Joboptions control because of a PDF standard, compatibility requirement, another setting, or a consistency rule.
- Every Joboptions parameter exposed by the UI must remain editable at all times. Imported Joboptions can bypass the editor completely, so UI restrictions cannot guarantee conversion correctness.
- Do not implement Joboptions consistency policy in macOS or iOS UI code. In particular, do not add UI-level checks that enforce, repair, override, or reject combinations of Joboptions values.
- Put every cross-setting, PDF-standard, compatibility, and conversion-correctness rule in `JoboptionsConsistencyEngine`.
- The settings UI may display the stored value, highlight affected rows, and present the issues reported by `JoboptionsConsistencyEngine`. It must not perform the repair itself as an implicit side effect of editing or displaying a control.
- Conversion must use the effective Joboptions produced by `JoboptionsConsistencyEngine`, so inconsistent stored or imported Joboptions are corrected deterministically at conversion time.
- Explicit user-requested consistency repair may update the stored Joboptions through the shared consistency-engine result. Otherwise, preserve the user's stored values.
- Preserve recognized but unsupported Joboptions keys losslessly unless an explicit product requirement says to remove them. Do not add consistency rules merely to delete harmless parameters.

## UI controls

- Boolean Joboptions controls have exactly two user-facing states: Yes and No. If a Boolean key is absent, display the value that the conversion runtime will use by default; do not expose an inherited, mixed, or “not set” state.
- Opening settings must not insert missing default values. Once the user changes a Boolean control, write the explicit Boolean key and keep it in the Joboptions so subsequent edits only toggle it.
- The same read-without-writing rule applies to menus and numeric fields. Missing selections use the concrete runtime default, never a transient “not set” menu item. “None” means an explicit absence of a standard or profile override, not an arbitrary enum default.
- Free-text fields with missing values are empty, without “not set” or “None” placeholders. Clearing text stores an explicit empty string; it does not delete the key.
- Context-dependent display defaults come from `JoboptionsConsistencyEngine`. Stored values, including inconsistent imported values, must not be masked by proposed repairs.
- Loading or refreshing a control must never trigger its user-edit callback, particularly SwiftUI draft/state observers.
- UI conditionals may be used for presentation and layout only. They must not encode consistency or conversion policy.
- Joboptions editors always display the user's stored values and keep every exposed control editable. This includes advanced iOS settings, the detailed macOS Joboptions editor (`MacOSDistillerEditorViewController`), and any other current or future editing surface.
- `MacOSSettingsViewController` contains only Ghostscript runtime settings. Joboptions selection and compact conversion choices belong to the start screen; Joboptions editing and management use their dedicated surfaces.
- Sole exception to the editing and stored-value display rules above: the compact start screen, currently presented through `FrontConversionView` on both iOS and macOS, contains the Joboptions, PDF version, and PDF/A dropdowns as a conversion shortcut. On this start screen, the PDF version dropdown must be disabled and visually grayed out whenever `JoboptionsConsistencyEngine` determines that the selected PDF/A setting constrains the PDF version, and must display the effective PDF version reported by that engine, even if it differs from the stored value. Both the constraint and the effective value must come from the engine; do not duplicate PDF/A-to-version rules in UI code or infer the constraint solely from the presence of a repair issue (the stored version may already match). When PDF/A does not constrain the version, the normal editing and display rules apply. This presentation must not modify stored Joboptions. This exception applies only to the PDF version dropdown on the compact start screen, not to any Joboptions editor or any other control.
