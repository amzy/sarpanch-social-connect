# Design System & Branding Rules

## Product rules
- The application interface is English only.
- Post content language is configured separately in the user profile and can be overridden per post.
- App appearance, Panchayat poster branding and social account identity are separate configuration domains.
- The master Sarpanch Social Connect logo does not change between themes.
- Official seals, government emblems and user photographs must never be automatically recolored.

## Themes
The app ships with six semantic theme palettes:
1. Government Blue
2. Gram Green
3. Saffron Orange
4. Royal Purple
5. Teal Cyan
6. Crimson Red

Each palette must work in Light, Dark and Follow System appearance modes. Screens must consume Theme.of(context).colorScheme or shared theme extensions; do not hardcode theme colors inside feature widgets.

## Components
Use Material 3 components with an iOS-first interaction and navigation feel. Shared components should define spacing, radii, typography, button hierarchy, cards, inputs, navigation, status indicators and loading/empty/error states.

## Poster branding
Poster templates use a separate Panchayat branding configuration. A user can select official tricolor-inspired poster styling even when the app itself uses another color theme. Keep safe margins, readable text, source attribution for government information and clear Before/After labels.

## Accessibility
Support dynamic text scaling, screen readers, visible labels, adequate touch targets, sufficient contrast and non-color status cues. Validate all six content scripts using real device fonts and text lengths.
