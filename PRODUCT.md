# Mac AutoKey
<!-- impeccable:product-schema 1 -->

## Platform
Native macOS desktop, macOS 14 or later.

## Stack
User-specified Swift, SwiftUI, AppKit, CoreGraphics, native global hotkeys. No external dependencies or runtime network access.

## Users and purpose
The user needs repeatable mouse clicks and editable ordered keyboard input, including a Citrix remote session. Success means reliable start, stop, persistence, and honest compatibility reporting.

## Operating context
Menu bar utility with a small two-tab configuration window. Test local input first; remote event acceptance depends on Citrix configuration and policies.

## Capabilities and constraints
Click interval 30–60,000 ms. Ordered keys, per-character text, and delays. Editable shortcuts, emergency stop, Accessibility onboarding, optional saved target allowlist. Never start automation at launch. Never bypass security policies.

## Brand commitments
Mac AutoKey; minimalist native macOS appearance, system fonts, SF Symbols, light and dark modes. This explicit brief determines the visual direction; user requested autonomous implementation without confirmation rounds.

## Evidence
Build and test evidence will be recorded in docs/TEST_RESULTS.md. No remote-session success may be inferred from mocks.
