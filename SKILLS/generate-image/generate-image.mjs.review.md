# Review Request: generate-image.mjs

Please review `/Users/juliovedovatto/.pi/agent/skills/generate-image/generate-image.mjs` for:

1. Correctness of the new input image feature
2. Opportunities to simplify code
3. Any edge cases or bugs
4. Whether the implementation matches requirements:
   - --input-image (repeatable)
   - --input-images (comma-separated)
   - --input-fidelity
   - Local file -> base64 data URI
   - Model-specific mapping (input_images, image_input, image)
   - input_fidelity default high for gpt-image-1.5 with input images
   - Warn for unsupported models
   - Don't attach if user explicitly set image fields via --options

Focus on keeping code simple and avoiding over-abstraction.
