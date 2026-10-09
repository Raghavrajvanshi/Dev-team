---
name: design-quality
description: What good product design looks like now, and the rubric used to judge UI work from screenshots.
user-invocable: false
---
# Design quality

Meeting a checklist is not the goal; a result a skeptical designer would respect is. Original work only: no proprietary logos, photography or fonts, but the *quality* of the references is the bar.

## Principles
- **One idea per section, one clear hierarchy.** Scale and weight contrast carry the page. A hero has a focal visual, not only text.
- **Systems, not styles.** Design tokens for colour roles, a modular type scale (fluid with `clamp()`), a spacing scale, radii, elevation and motion timings. No magic numbers.
- **Imagery is half the design.** Without licensed photography, make rich original visuals: layered SVG, gradients and lighting, CSS 3D transforms, generated patterns. Flat clip-art boxes are a defect.
- **Depth and finish.** Subtle shadows and blur, considered colour and contrast, consistent radii, crisp alignment on a grid. No orphan cells or ragged rows.
- **Motion with purpose.** Scroll reveals and state transitions that clarify, never decorate; always honour `prefers-reduced-motion`.
- **Every state exists.** Hover, focus-visible, active, disabled, loading, empty, error, and long or missing content.
- **Responsive by design.** Composition changes at 390, 768 and 1280 widths, not just shrinking. Touch targets 44px.
- **Content depth.** Real, specific copy and enough sections to tell the story. No lorem ipsum, no repeated filler.
- **Modern and fast.** Current platform features (container queries, `:has`, view transitions where supported), semantic HTML, accessible by default (contrast 4.5:1, landmarks, labels), images sized and lazy-loaded.

## Rubric (score each 1-5; excellent work is 4 or above on every line)
hierarchy · typography · spacing and rhythm · colour and contrast · imagery and visual richness · depth and polish · motion and interaction · responsiveness · content depth · fidelity to the reference and the spec.
Anchors: 1 = broken or wireframe-like; 3 = competent but generic; 4 = polished and intentional; 5 = distinctive and delightful.

## Rules for judging
Judge only from screenshots you have opened (`Read` on the image) at 390, 768 and 1280. Quote what you see for any score under 4 and name the exact fix.
