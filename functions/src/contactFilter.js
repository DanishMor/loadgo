'use strict';
// F17: a port of lib/core/comm/contact_filter.dart. It finds phone numbers,
// UPI ids, other apps and "call me" in a chat message. The Dart file is the
// original; test/fixtures/contact_cases.json holds the answers of the Dart code
// for a large set of texts and the tests here must give the same answers.
// Keep both in step: change the Dart filter, regenerate the fixture
// (flutter test tool/make_contact_fixture_test.dart), then fix this file.

const KIND = Object.freeze({ phone: 'phone', upi: 'upi', app: 'app', payment: 'payment' });

// First code point of each script's digit block (0..9 follow in order).
const DIGIT_BLOCKS = [0x0660, 0x06f0, 0x0966, 0x09e6, 0x0a66, 0x0ae6, 0x0b66, 0x0be6, 0x0c66, 0x0ce6, 0xff10];

function normalise(input) {
  let out = '';
  for (const ch of input) {
    const r = ch.codePointAt(0);
    if (r === 0xfe0f || r === 0x20e3 || r === 0x200b || r === 0x200c || r === 0x200d || r === 0x2060 || r === 0xad) continue;
    let mapped = false;
    for (const base of DIGIT_BLOCKS) {
      if (r >= base && r <= base + 9) {
        out += String.fromCharCode(0x30 + r - base);
        mapped = true;
        break;
      }
    }
    if (!mapped) out += ch.toLowerCase();
  }
  return out;
}

const upi = new RegExp(String.raw`[a-z0-9._\-]+\s?@\s?[a-z]{2,}`);
const link = new RegExp(String.raw`https?\s?:\s?//|www\s?\.|\b(?:t\.me|wa\.me|bit\.ly|tinyurl)\b`);
const appNames = new RegExp(String.raw`whatsapp|whatsap|watsapp|whtsapp|wtsapp|telegram|telegrm|instagram|facebook|messenger`);
const appWords = new RegExp(String.raw`\b(?:wa|whats\s?app|watsap|tg|insta|fb)\b`);
const askPhrases = new RegExp(
  String.raw`call\s*me|call\s*(?:kar|kr)(?:o|na|do|dena|lo)?\b|phone\s*(?:kar|kr)(?:o|na|do)?\b|fone\s*(?:kar|kr)(?:o|na)?\b|ring\s*me|contact\s*me|dm\s*me|text\s*me|` +
    String.raw`(?:mobile|mobil|phone|fone|contact|personal|direct|whats\s?app)\s*(?:no\.?|number|nmbr|nambar|num)\b|` +
    String.raw`(?:apna|apne|mera|meri|tera|teri|tumhara|aapka|aapke|your|my)\s*(?:mobile\s*|phone\s*|contact\s*)?(?:no\.?|number|nmbr|nambar|num)\b|` +
    String.raw`number\s*(?:share|send)\b|share\s*(?:your\s*)?number|` +
    String.raw`\bmy\s*(?:upi|gpay|phonepe|paytm)\b|\b(?:gpay|google\s*pay|phonepe|phone\s*pe|paytm|bhim)\s*(?:number|no\b|id\b)|` +
    String.raw`कॉल\s*कर|फ़?ोन\s*कर|फोन\s*नंबर|मोबाइल\s*नंबर|मोबाइल\s*नं|कॉन्टैक्ट|व्हाट्?स?एप|वॉट्?स?एप|व्हाट्सऐप|टेलीग्राम|अपना\s*नंबर|मेरा\s*नंबर|आपका\s*नंबर|तेरा\s*नंबर|नंबर\s*(?:दो|दे|दें|भेज|बता)`,
);
const payOutside = new RegExp(
  String.raw`pay\s*(?:me\s*)?outside|outside\s*(?:the\s*)?app|direct\s*payment|pay\s*direct(?:ly)?|bahar\s*(?:se\s*)?payment|app\s*ke\s*bahar|` +
    String.raw`cash\s*(?:me|mein)\s*(?:de|do)\s*dena|(?:google\s*pay|phone\s*pe|gpay)\s*kar|ऐप\s*के\s*बाहर|बाहर\s*(?:से\s*)?पेमेंट|सीधे\s*पेमेंट`,
);
const date = new RegExp(
  String.raw`\b(?:(?:19|20)\d\d[-/.](?:0?[1-9]|1[0-2])[-/.](?:0?[1-9]|[12]\d|3[01])|(?:0?[1-9]|[12]\d|3[01])[-/.](?:0?[1-9]|1[0-2])[-/.](?:(?:19|20)\d\d|\d\d))\b`,
  'g',
);

const WORD_DIGITS = new Map(
  Object.entries({
    zero: 0, shunya: 0, sifar: 0, shoonya: 0, शून्य: 0, सिफर: 0, जीरो: 0,
    one: 1, ek: 1, एक: 1,
    two: 2, do: 2, दो: 2,
    three: 3, teen: 3, tin: 3, तीन: 3,
    four: 4, char: 4, chaar: 4, चार: 4,
    five: 5, paanch: 5, panch: 5, pach: 5, पांच: 5, पाँच: 5,
    six: 6, chhe: 6, chhah: 6, chha: 6, chah: 6, chhay: 6, छह: 6, छः: 6, छे: 6, छ: 6,
    seven: 7, saat: 7, sat: 7, सात: 7,
    eight: 8, aath: 8, ath: 8, आठ: 8,
    nine: 9, nau: 9, nao: 9, नौ: 9, नो: 9,
  }),
);
const MULTIPLIERS = new Map(Object.entries({ double: 1, dabal: 1, dubal: 1, डबल: 1, triple: 2, tripal: 2, ट्रिपल: 2 }));

const WORD = /[a-z]+|[ऀ-ॿ]+|\d+/g;
const DIGITS_ONLY = /^\d+$/;
const GAP = /^[\s.,\-_/()+*#|;~]*$/;
const TIME = new RegExp(String.raw`\b\d{1,2}\s?:\s?\d{2}\b(?:\s?(?:am|pm))?`, 'g');

function clip(s) {
  return s.length <= 6000 ? s : `${s.slice(0, 3000)} ${s.slice(s.length - 3000)}`;
}

function looksLikePhone(full) {
  if (full.startsWith('0') && full.length >= 10 && full.length <= 11) return true;
  let d = full;
  if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
  if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
  if (d.length < 8 || d.length > 12) return false;
  if (/^[6-9]/.test(d)) return true;
  return d.startsWith('0') && d.length >= 10;
}

function numberChain(t) {
  let full = '';
  let multiplier = 0;
  let lastEnd = -1;
  let started = false;

  function decide() {
    const ok = started && looksLikePhone(full);
    full = '';
    multiplier = 0;
    started = false;
    return ok;
  }

  function add(digits) {
    if (digits.length === 0) return;
    full += digits[0].repeat(1 + multiplier);
    full += digits.slice(1);
    multiplier = 0;
    started = true;
  }

  for (const m of t.matchAll(WORD)) {
    const w = m[0];
    const joined = lastEnd < 0 || GAP.test(t.slice(lastEnd, m.index));
    lastEnd = m.index + w.length;
    if (!joined && started && decide()) return true;
    if (DIGITS_ONLY.test(w)) {
      add(w);
      continue;
    }
    if (WORD_DIGITS.has(w)) {
      add(String(WORD_DIGITS.get(w)));
      continue;
    }
    if (MULTIPLIERS.has(w)) {
      multiplier = MULTIPLIERS.get(w);
      continue;
    }
    if (decide()) return true;
  }
  return decide();
}

function scan(raw) {
  const t = clip(normalise(raw));
  if (t.trim().length === 0) return null;
  if (upi.test(t)) return KIND.upi;
  if (numberChain(t.replace(date, ' ').replace(TIME, ' '))) return KIND.phone;
  if (link.test(t) || appNames.test(t) || appWords.test(t) || askPhrases.test(t)) return KIND.app;
  const squashed = t.replace(/[\s.\-_*]+/g, '');
  if (appNames.test(squashed)) return KIND.app;
  if (payOutside.test(t)) return KIND.payment;
  return null;
}

// recent: the sender's own latest messages, newest first.
function check(text, recent = []) {
  const own = scan(String(text ?? ''));
  if (own !== null) return own;
  const before = recent.slice(0, 3).reverse();
  if (before.length === 0) return null;
  const joined = scan([...before, String(text ?? '')].join(' '));
  return joined === KIND.phone ? joined : null;
}

module.exports = { KIND, check, normalise };
