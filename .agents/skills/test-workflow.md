---
name: test-workflow
description: Verifies basic file system tools by performing write, edit, read, and delete operations in sequence.
---

# Test Workflow

Perform the following steps to verify local file system access:

1. **Create**: Use `write` to create a temporary file (e.g., `test_skill.txt`) with sample content.
2. **Modify**: Use `edit` to change a specific string in that file.
3. **Verify**: Use `read` to confirm the change was applied correctly.
4. **Cleanup**: Use `run` with `Remove-Item` or similar command to delete the temporary file.

Confirm success after each step.
