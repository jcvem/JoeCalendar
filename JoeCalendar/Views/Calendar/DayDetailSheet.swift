//
//  DayDetailSheet.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Phase 1 Core Calendar.
//  Convenience wrapper presenting EventFormSheet.
//

import SwiftUI

public struct DayDetailSheet: View {
    private let selectedDate: Date
    private let onSave: ((CalendarEvent) -> Void)?
    
    public init(selectedDate: Date, onSave: ((CalendarEvent) -> Void)? = nil) {
        self.selectedDate = selectedDate
        self.onSave = onSave
    }
    
    public var body: some View {
        EventFormSheet(mode: .new(defaultDate: selectedDate))
    }
}
