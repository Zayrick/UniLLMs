//
//  DateTimeTool.swift
//  UniLLMs
//
//  Provides a minimal built-in date-time tool implementation for validating the tool registration and execution path.
//  Created by Zayrick on 2026/5/11.
//

import Foundation

struct DateTimeTool: Tool {
    let definition = ToolDefinition(
        name: "current_datetime",
        displayName: "Current Date and Time",
        summary: "Returns the current local date and time."
    )

    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        ToolResult(callID: call.id, content: Date().formatted(date: .complete, time: .complete))
    }
}
