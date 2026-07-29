import Testing
import Foundation
import CoreData
@testable import LillistCore

/// The class-killer for X3 (and the `SmartFilter`/`defaultTagTintHex` gaps
/// discovered alongside it): walks every entity in the live Core Data model
/// and asserts each attribute/relationship is either mapped into an
/// `ExportSchema` DTO field (directly, or via a documented rename) or on an
/// explicit exclusion list carrying a non-empty rationale. Adding a new
/// entity, attribute, or relationship to the model without deciding its
/// export fate fails this test by name — it cannot silently ship the way
/// `SmartFilter` (zero mapping at all) and `defaultTagTintHex` (one missed
/// field) did.
///
/// The mapping tables below are the source of truth referenced by
/// `docs/superpowers/plans/2026-07-28-plan-1d-export-schema-completeness.md`'s
/// *Full entity/attribute/relationship disposition* section — keep them in
/// sync; this test enforces they stay in sync with the model, not with each
/// other.
@Suite("Export schema completeness (model-derived)")
struct ExportSchemaCompletenessTests {
    /// One Core Data entity's disposition.
    private struct EntityMapping {
        /// Core Data attribute/relationship name -> DTO field name, only
        /// where they differ (e.g. `statusRaw` -> `status`). Anything not
        /// listed here is expected to appear in the DTO under its own name.
        let renames: [String: String]
        /// Core Data attribute/relationship name -> exclusion rationale.
        /// Every value must be non-empty (enforced below) — an exclusion
        /// with no stated reason is exactly the kind of silent drop this
        /// test exists to catch.
        let excluded: [String: String]
    }

    private static let mappings: [String: EntityMapping] = [
        "LillistTask": EntityMapping(
            renames: ["statusRaw": "status", "parent": "parentID", "tags": "tagIDs", "series": "seriesID"],
            excluded: [
                "children": "derived inverse of parent; reconstructed on import from every child's own parentID",
                "journalEntries": "derived inverse of JournalEntry.task; reconstructed from JournalEntryDTO.taskID",
                "attachments": "derived inverse of Attachment.task/journalEntry; reconstructed from AttachmentDTO.taskID/journalEntryID",
                "seriesAsSeed": "derived inverse of Series.seedTask; reconstructed from SeriesDTO.seedTaskID",
                "notificationSpecs": "derived inverse of NotificationSpec.task; reconstructed from NotificationSpecDTO.taskID",
            ]
        ),
        "Tag": EntityMapping(
            renames: ["parent": "parentID"],
            excluded: [
                "children": "derived inverse of parent; reconstructed on import from every child's own parentID",
                "tasks": "derived inverse of LillistTask.tags; reconstructed from TaskDTO.tagIDs",
            ]
        ),
        "JournalEntry": EntityMapping(
            renames: ["kindRaw": "kind", "task": "taskID"],
            excluded: [
                "attachments": "derived inverse of Attachment.journalEntry; reconstructed from AttachmentDTO.journalEntryID",
            ]
        ),
        "Attachment": EntityMapping(
            renames: ["kindRaw": "kind", "data": "dataPath", "task": "taskID", "journalEntry": "journalEntryID"],
            excluded: [:]
        ),
        "AppPreferences": EntityMapping(
            renames: [
                "defaultAllDayNotificationHour": "defaultAllDayHour",
                "defaultAllDayNotificationMinute": "defaultAllDayMinute",
                "defaultTaskListSortRaw": "defaultTaskListSort",
            ],
            excluded: [
                "id": "well-known singleton row (PreferencesStore.singletonID) — import always targets it directly, no id needed",
                "crashPromptsEnabled": "Plan 21 device-local partition (DevicePreferencesStore) — must not sync/export; see AppPreferencesPartitionMigrator",
                "hasCompletedOnboarding": "Plan 21 device-local partition (DevicePreferencesStore) — must not sync/export; see AppPreferencesPartitionMigrator",
                "quickCaptureEnabled": "Plan 21 device-local partition (DevicePreferencesStore) — must not sync/export; see AppPreferencesPartitionMigrator",
                "quickCaptureHotkey": "Plan 21 device-local partition (DevicePreferencesStore) — must not sync/export; see AppPreferencesPartitionMigrator",
                "statusBarItemVisible": "Plan 21 device-local partition (DevicePreferencesStore) — must not sync/export; see AppPreferencesPartitionMigrator",
            ]
        ),
        "SmartFilter": EntityMapping(
            renames: ["predicateGroupJSON": "predicateGroup", "sortFieldRaw": "sortField"],
            excluded: [:]
        ),
        "Series": EntityMapping(
            renames: ["ruleJSON": "rule", "seedTask": "seedTaskID"],
            excluded: [
                "instances": "derived inverse of LillistTask.series; reconstructed from every instance task's own seriesID",
            ]
        ),
        "NotificationSpec": EntityMapping(
            renames: ["kindRaw": "kind", "task": "taskID"],
            excluded: [:]
        ),
    ]

    private static func dtoFieldNames(forEntity name: String) -> Set<String>? {
        switch name {
        case "LillistTask":
            return fieldNames(of: ExportSchema.TaskDTO(
                id: UUID(), title: "", notes: "", status: 0, start: nil, startHasTime: false,
                deadline: nil, deadlineHasTime: false, position: 0, isPinned: false, parentID: nil,
                tagIDs: [], createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil
            ))
        case "Tag":
            return fieldNames(of: ExportSchema.TagDTO(id: UUID(), name: "", tintColor: nil, parentID: nil, position: 0))
        case "JournalEntry":
            return fieldNames(of: ExportSchema.JournalEntryDTO(
                id: UUID(), taskID: nil, kind: 0, body: "", payload: nil, createdAt: nil, editedAt: nil
            ))
        case "Attachment":
            return fieldNames(of: ExportSchema.AttachmentDTO(
                id: UUID(), taskID: nil, journalEntryID: nil, kind: 0, filename: "", uti: "",
                byteSize: 0, dataPath: nil, linkPreviewJSON: nil, createdAt: nil
            ))
        case "AppPreferences":
            return fieldNames(of: ExportSchema.PreferencesDTO.fallback)
        case "SmartFilter":
            return fieldNames(of: ExportSchema.SmartFilterDTO(
                id: UUID(), name: "", predicateGroup: nil, tintColor: nil, sortField: "",
                sortAscending: false, isPinned: false, position: 0, createdAt: nil, modifiedAt: nil
            ))
        case "Series":
            return fieldNames(of: ExportSchema.SeriesDTO(id: UUID(), seedTaskID: nil, rule: nil, nextOccurrenceAfter: nil))
        case "NotificationSpec":
            return fieldNames(of: ExportSchema.NotificationSpecDTO(
                id: UUID(), taskID: nil, kind: 0, offsetMinutes: nil, fireDate: nil,
                lastFiredAt: nil, snoozedUntil: nil, createdAt: nil
            ))
        default:
            return nil
        }
    }

    private static func fieldNames(of instance: Any) -> Set<String> {
        Set(Mirror(reflecting: instance).children.compactMap(\.label))
    }

    @Test("Every model entity's attributes/relationships are exported (directly or via a documented rename) or explicitly excluded with a rationale")
    func modelCompleteness() throws {
        let model = try PersistenceController.sharedModel()
        for entity in model.entities {
            guard let entityName = entity.name else { continue }
            guard let mapping = Self.mappings[entityName] else {
                Issue.record("Entity '\(entityName)' has no completeness mapping at all — add one to ExportSchemaCompletenessTests.mappings")
                continue
            }
            guard let dtoFields = Self.dtoFieldNames(forEntity: entityName) else {
                Issue.record("Entity '\(entityName)' has a mapping table entry but no case in dtoFieldNames(forEntity:)")
                continue
            }
            let properties = Array(entity.attributesByName.keys) + Array(entity.relationshipsByName.keys)
            for property in properties {
                if let rationale = mapping.excluded[property] {
                    #expect(!rationale.isEmpty, "\(entityName).\(property) is on the exclusion list with an empty rationale")
                    continue
                }
                let expectedDTOName = mapping.renames[property] ?? property
                #expect(
                    dtoFields.contains(expectedDTOName),
                    "\(entityName).\(property) is neither mapped to a DTO field ('\(expectedDTOName)') nor explicitly excluded with a rationale"
                )
            }
        }
    }
}
