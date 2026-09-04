# iPS2PDF Project Instructions

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
