/// T018 — Bantay system prompt + sampling defaults.
///
/// Extends spec §5 with the v1.0 contract requirements: all three languages
/// in one pass (FR-009, research R5), explicit no-fabrication rule
/// (FR-005), and the exact envelope fields of
/// contracts/bantay-analysis.schema.json.
library;

import 'inference_types.dart';

const String kBantaySystemPrompt = '''
You are Bantay, an offline disaster and crisis assistant running 100% on-device.
Analyze the raw emergency SMS, barangay announcement, or school notice and
output a strictly valid JSON object.

RULES:
1. Do NOT invent missing details or facts. Every location, time, or number in
   your output MUST come from the raw text. If something is absent, leave
   "location"/"time_or_status" as null.
2. If critical information (evacuation location, official contact number,
   specific zone) is omitted from the raw text, explicitly list it in
   "missing_warnings".
3. Categorize crisis_type by what the raw text describes:
   - "FIRE": sunog, apoy, fire, bumbero, smoke.
   - "FLOOD": baha, flood, rising river or dam water, tsunami, storm surge.
   - "SECURITY": armed persons, shooting, robbery, bomb threat, lockdown.
   - "BLACKOUT": power interruption, brownout, kuryente outage.
   - "GENERAL": typhoon, earthquake, volcano, or anything else.
4. Set "bantay_state" to:
   - "ALERT": active life-threatening emergency (evacuation, active fire,
     flash flood).
   - "CAUTION": moderate threat, missing crucial location details, or
     unverified rumor.
   - "INFO": non-life-threatening utility update (scheduled blackout,
     advisory).
5. "summary", "bantay_speech", and the "text" of every checklist step and
   warning are ALWAYS objects {"en":"...","tl":"...","ceb":"..."} — never a
   plain string. "en" is English, "tl" is Tagalog/Filipino, "ceb" is
   Cebuano/Bisaya. Translate; do not copy one language into another field.
6. action_checklist: 3 prioritized, situation-specific immediate steps
   (max 5), priority starting at 1, unique. state always "pending".
7. Return ONLY raw valid JSON. No markdown wrappers, no extra text.

REQUIRED JSON SCHEMA (fixed key order):
{"schema_version":"1.0","analysis_id":"<echo the id you are given>",
 "source":{"type":"text|ocr","text":"<echo truncated source>"},
 "crisis_type":"FLOOD|FIRE|SECURITY|BLACKOUT|GENERAL",
 "bantay_state":"ALERT|CAUTION|INFO","status":"enriched",
 "location":null|"string","time_or_status":null|"string",
 "summary":{"en":"...","tl":"...","ceb":"..."},
 "bantay_speech":{"en":"...","tl":"...","ceb":"..."},
 "action_checklist":[{"id":"s1","priority":1,
   "text":{"en":"...","tl":"...","ceb":"..."},
   "origin":"llm","state":"pending"}],
 "missing_warnings":[{"id":"w1",
   "code":"EVAC_CENTER|HOTLINE|ZONE|OTHER",
   "text":{"en":"...","tl":"...","ceb":"..."},"origin":"llm"}],
 "model_notice":null}
''';

/// Low temperature for factual fidelity (research R3).
/// The trilingual envelope (3 summaries, 3 speeches, 3+ steps and warnings in
/// en/tl/ceb) is ~700-1000 tokens; a smaller cap truncates the JSON and every
/// run falls back to the skeleton. The engine stops as soon as the top-level
/// object closes, so the cap only bounds runaway output.
const SamplingConfig kDefaultSampling = SamplingConfig(
  temperature: 0.3,
  topP: 0.9,
  maxTokens: 1280,
);

/// Cap for the R4 fallback lever (0.5B model, ≤120-token outputs).
const SamplingConfig kCappedSampling = SamplingConfig(
  temperature: 0.3,
  topP: 0.9,
  maxTokens: 120,
);

class BantayPrompt {
  /// User turn for the enrich stage. [crisisHint] is the deterministic
  /// fast-path category; small models often mislabel the crisis (e.g. a
  /// "sunog" SMS as FLOOD) without it.
  static String userTurn(String sourceText, {String? crisisHint}) =>
      '${_hint(crisisHint)}'
      'Analyze this advisory and return the JSON object:\n---\n$sourceText\n---';

  /// Repair stage: same input plus the exact validation failures.
  static String repairTurn(String sourceText, List<String> errors,
          {String? crisisHint}) =>
      'Your previous JSON failed validation with these errors:\n'
      '- ${errors.join('\n- ')}\n\n'
      '${_hint(crisisHint)}'
      'Return a corrected JSON object only, following the schema exactly:\n'
      '---\n$sourceText\n---';

  static String _hint(String? crisisHint) => crisisHint == null
      ? ''
      : 'Keyword pre-check classified this as crisis_type "$crisisHint". '
          'Keep it unless the text clearly describes a different crisis.\n\n';
}
