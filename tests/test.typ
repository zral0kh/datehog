// datehog unit tests.
//
// Every check is an `assert`, so the suite passes exactly when this file
// runs cleanly -- nothing renders, so there is no PDF to compile. Run with
// `tests/run.sh`, or:
//
//   typst eval --root . --in tests/test.typ '"ok"'
//
// Differential tests against V8 and flint-py live in `compare.py`; this file
// covers the arithmetic and the edges that have no external reference.

#import "../src/lib.typ" as dh
#import "../src/civil.typ": civil-from-days, days-from-civil, days-in-month, is-leap-year, is-valid-date, weekday-from-days

#let check(name, actual, expected) = {
  assert(
    actual == expected,
    message: name + ": expected " + repr(expected) + ", got " + repr(actual),
  )
}

// ── leap years ─────────────────────────────────────────────────────────────
#check("leap 2020", is-leap-year(2020), true)
#check("leap 1900", is-leap-year(1900), false)
#check("leap 2000", is-leap-year(2000), true)
#check("leap 2021", is-leap-year(2021), false)
#check("leap 0", is-leap-year(0), true)
#check("leap -4", is-leap-year(-4), true)

#check("days in Feb 2020", days-in-month(2020, 2), 29)
#check("days in Feb 2021", days-in-month(2021, 2), 28)
#check("days in Feb 1900", days-in-month(1900, 2), 28)
#check("days in Dec", days-in-month(2021, 12), 31)
#check("days in month 13", days-in-month(2021, 13), 0)

// ── civil <-> days ─────────────────────────────────────────────────────────
#check("epoch day 0", days-from-civil(1970, 1, 1), 0)
#check("day before epoch", days-from-civil(1969, 12, 31), -1)
#check("2020-03-14", days-from-civil(2020, 3, 14), 18335)
#check("civil from 0", civil-from-days(0), (1970, 1, 1))
#check("civil from -1", civil-from-days(-1), (1969, 12, 31))
#check("civil from 18335", civil-from-days(18335), (2020, 3, 14))

// Round-trip across century and leap boundaries, including pre-epoch.
#let _roundtrip-days = (
  -719468, -100000, -1, 0, 1, 11016, 18335, 25000, 100000, 2932896,
)
#for d in _roundtrip-days {
  let (y, m, dd) = civil-from-days(d)
  check("roundtrip day " + str(d), days-from-civil(y, m, dd), d)
}

// Every day of a leap year round-trips.
#let _leap-start = days-from-civil(2020, 1, 1)
#for i in range(366) {
  let (y, m, d) = civil-from-days(_leap-start + i)
  assert(
    days-from-civil(y, m, d) == _leap-start + i,
    message: "leap-year roundtrip failed at offset " + str(i),
  )
}

// ── weekdays ───────────────────────────────────────────────────────────────
#check("1970-01-01 was Thursday", weekday-from-days(0), 4)
#check("2020-03-14 was Saturday", weekday-from-days(days-from-civil(2020, 3, 14)), 6)
#check("2000-01-01 was Saturday", weekday-from-days(days-from-civil(2000, 1, 1)), 6)

// ── date validation ────────────────────────────────────────────────────────
#check("valid 2020-02-29", is-valid-date(2020, 2, 29), true)
#check("invalid 2019-02-29", is-valid-date(2019, 2, 29), false)
#check("invalid month 0", is-valid-date(2020, 0, 1), false)
#check("invalid day 0", is-valid-date(2020, 1, 0), false)
#check("invalid day 32", is-valid-date(2020, 1, 32), false)

// ── moments ────────────────────────────────────────────────────────────────
#let m = dh.from-ms(1584174600250)
#check("moment year", m.year, 2020)
#check("moment month", m.month, 3)
#check("moment day", m.day, 14)
#check("moment hour", m.hour, 8)
#check("moment minute", m.minute, 30)
#check("moment second", m.second, 0)
#check("moment ms", m.millisecond, 250)
#check("moment weekday", m.weekday, 6)
#check("moment ordinal", m.ordinal, 74)
#check("moment iso", dh.to-iso(m), "2020-03-14T08:30:00.250Z")
#check("moment iso date", dh.to-iso-date(m), "2020-03-14")
#check("is-moment", dh.is-moment(m), true)
#check("is-moment on dict", dh.is-moment((year: 2020)), false)

// Pre-epoch instants keep positive time-of-day fields.
#let pre = dh.from-ms(-14182940000)
#check("pre-epoch iso", dh.to-iso(pre), "1969-07-20T20:17:40.000Z")
#check("pre-epoch year", pre.year, 1969)
#check("pre-epoch hour", pre.hour, 20)

// Fractional and non-finite input.
#check("from-ms floors", dh.from-ms(1584174600250.9).millisecond, 250)
#check("from-ms nan", dh.from-ms(float.nan), none)
#check("from-ms inf", dh.from-ms(float.inf), none)
#check("from-ms none", dh.from-ms(none), none)

// Round-trip through the epoch.
#check("ms roundtrip", dh.to-ms(dh.from-ms(1584174600250)), 1584174600250)

// ── from-parts normalisation ───────────────────────────────────────────────
#check("month 13 rolls over", dh.to-iso-date(dh.from-parts(2020, 13, 1)), "2021-01-01")
#check("month 0 rolls back", dh.to-iso-date(dh.from-parts(2020, 0, 1)), "2019-12-01")
#check("day 0 rolls back", dh.to-iso-date(dh.from-parts(2020, 1, 0)), "2019-12-31")
#check("day 32 rolls over", dh.to-iso-date(dh.from-parts(2020, 1, 32)), "2020-02-01")

// ── arithmetic ─────────────────────────────────────────────────────────────
#check("add-days", dh.to-iso-date(dh.add-days(dh.from-parts(2020, 2, 28), 1)), "2020-02-29")
#check("add-days over year", dh.to-iso-date(dh.add-days(dh.from-parts(2020, 12, 31), 1)), "2021-01-01")
#check("add-months clamps", dh.to-iso-date(dh.add-months(dh.from-parts(2020, 1, 31), 1)), "2020-02-29")
#check("add-months clamps non-leap", dh.to-iso-date(dh.add-months(dh.from-parts(2021, 1, 31), 1)), "2021-02-28")
#check("add-months back", dh.to-iso-date(dh.add-months(dh.from-parts(2020, 3, 15), -3)), "2019-12-15")
#check("add-ms", dh.to-ms(dh.add-ms(dh.from-ms(1000), 500)), 1500)

// ── ISO parsing ────────────────────────────────────────────────────────────
#check("iso date", dh.to-iso(dh.parse-iso("2020-03-14")), "2020-03-14T00:00:00.000Z")
#check("iso year-month", dh.to-iso-date(dh.parse-iso("2020-03")), "2020-03-01")
#check("iso year", dh.to-iso-date(dh.parse-iso("2020")), "2020-01-01")
#check("iso datetime", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00")), "2020-03-14T08:30:00.000Z")
#check("iso with Z", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00Z")), "2020-03-14T08:30:00.000Z")
#check("iso with offset", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00+02:00")), "2020-03-14T06:30:00.000Z")
#check("iso offset no colon", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00-0500")), "2020-03-14T13:30:00.000Z")
#check("iso millis", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00.25Z")), "2020-03-14T08:30:00.250Z")
#check("iso nanos truncate", dh.to-iso(dh.parse-iso("2020-03-14T08:30:00.123456789Z")), "2020-03-14T08:30:00.123Z")
#check("iso space separator", dh.to-iso-date(dh.parse-iso("2020-03-14 08:30")), "2020-03-14")
#check("iso hour 24", dh.to-iso(dh.parse-iso("2020-03-14T24:00:00Z")), "2020-03-15T00:00:00.000Z")
#check("iso hour 24 with minutes rejected", dh.parse-iso("2020-03-14T24:30:00Z"), none)
#check("iso invalid day", dh.parse-iso("2020-02-30"), none)
#check("iso non-leap 29 Feb", dh.parse-iso("2019-02-29"), none)
#check("iso garbage", dh.parse-iso("hello"), none)
#check("iso non-string", dh.parse-iso(42), none)

#check("is-iso-date-only date", dh.is-iso-date-only("2020-03-14"), true)
#check("is-iso-date-only month", dh.is-iso-date-only("2020-03"), true)
#check("is-iso-date-only datetime", dh.is-iso-date-only("2020-03-14T08:00:00"), false)

// ── numeric parsing (V8 rules) ─────────────────────────────────────────────
#check("US order", dh.to-iso-date(dh.parse-numeric("01/15/2020")), "2020-01-15")
#check("year first", dh.to-iso-date(dh.parse-numeric("2020-01-15")), "2020-01-15")
#check("dots", dh.to-iso-date(dh.parse-numeric("01.15.2020")), "2020-01-15")
#check("day-first rejected", dh.parse-numeric("15.01.2020"), none)
#check("mixed separators rejected", dh.parse-numeric("01/15-2020"), none)
#check("no four-digit part rejected", dh.parse-numeric("1/2/3"), none)
#check("month 13 rejected", dh.parse-numeric("13/15/2020"), none)
#check("shape but unparseable", dh.is-numeric-date-shape("15.01.2020"), true)

// ── loose parsing ──────────────────────────────────────────────────────────
#check("mon year", dh.to-iso-date(dh.parse-loose("Feb 2020")), "2020-02-01")
#check("full month year", dh.to-iso-date(dh.parse-loose("February 2020")), "2020-02-01")
#check("mon day year", dh.to-iso-date(dh.parse-loose("Feb 15 2020")), "2020-02-15")
#check("mon day, year", dh.to-iso-date(dh.parse-loose("February 15, 2020")), "2020-02-15")
#check("day mon year", dh.to-iso-date(dh.parse-loose("15 Feb 2020")), "2020-02-15")
#check("ordinal suffix", dh.to-iso-date(dh.parse-loose("15th February 2020")), "2020-02-15")
#check("sept", dh.to-iso-date(dh.parse-loose("Sept 2020")), "2020-09-01")
#check("abbrev with dot", dh.to-iso-date(dh.parse-loose("Jan. 2020")), "2020-01-01")
#check("rfc2822", dh.to-iso(dh.parse-loose("Tue, 15 Feb 2020 08:30:00 GMT")), "2020-02-15T08:30:00.000Z")
#check("rfc2822 offset", dh.to-iso(dh.parse-loose("15 Feb 2020 08:30:00 +0200")), "2020-02-15T06:30:00.000Z")
#check("not a month name", dh.parse-loose("Xyz 2020"), none)

#check("word plus year", dh.year-from-words("FY 2018"), 2018)
#check("words plus year", dh.year-from-words("hello world 2018"), 2018)
#check("digit in word rejected", dh.year-from-words("Q1 2018"), none)
#check("two years rejected", dh.year-from-words("2018 2019"), none)
#check("no year", dh.year-from-words("hello"), none)

#check("two-digit year 20", dh.expand-two-digit-year("20"), "2020")
#check("two-digit year 99", dh.expand-two-digit-year("99"), "1999")
#check("two-digit year 49", dh.expand-two-digit-year("49"), "2049")
#check("two-digit year 50", dh.expand-two-digit-year("50"), "1950")
#check("four-digit passes through", dh.expand-two-digit-year("2020"), "2020")

// ── the JS layer ───────────────────────────────────────────────────────────
#check("js numbers pass through", dh.js.parse-ms(1584174600000), 1584174600000)
#check("js bool true", dh.js.parse-ms(true), 1)
#check("js none", dh.js.parse-ms(none), none)
#check("js empty string", dh.js.parse-ms(""), none)
#check("js whitespace", dh.js.parse-ms("   "), none)
#check("js FY", dh.to-iso-date(dh.parse("FY 2018")), "2018-01-01")
#check("js rejects day-first numeric", dh.parse-ms("15.01.2020"), none)
#check("js is-parseable", dh.is-parseable("2020-03-14"), true)
#check("js not parseable", dh.is-parseable("Wk 01"), false)
#check("js nan", dh.js.parse-ms(float.nan), none)

#check("timestamp seconds", dh.js.is-likely-timestamp(1584174600), true)
#check("timestamp millis", dh.js.is-likely-timestamp(1584174600000), true)
#check("small number not timestamp", dh.js.is-likely-timestamp(2020), false)
#check("bool not timestamp", dh.js.is-likely-timestamp(true), false)
#check("seconds scaled", dh.js.timestamp-to-ms(1584174600), 1584174600000)
#check("millis untouched", dh.js.timestamp-to-ms(1584174600000), 1584174600000)

// ── assume-offset ──────────────────────────────────────────────────────────
// A zoneless string read as if it were in UTC+2.
#check(
  "assume-offset shifts zoneless",
  dh.to-iso(dh.parse-iso("2020-03-14T08:30:00", assume-offset: 120)),
  "2020-03-14T06:30:00.000Z",
)
// An explicit zone always wins over assume-offset.
#check(
  "explicit zone wins",
  dh.to-iso(dh.parse-iso("2020-03-14T08:30:00Z", assume-offset: 120)),
  "2020-03-14T08:30:00.000Z",
)

// ── Typst datetime interop ─────────────────────────────────────────────────
#check(
  "from typst datetime",
  dh.to-iso-date(dh.from-typst-datetime(datetime(year: 2020, month: 3, day: 14))),
  "2020-03-14",
)
#check("to typst datetime", dh.to-typst-datetime(m).year(), 2020)

// ── month / weekday names ──────────────────────────────────────────────────
#check("month name", dh.month-name(3), "March")
#check("month abbr", dh.month-name(3, abbreviated: true), "Mar")
#check("month from name", dh.month-from-name("march"), 3)
#check("month from abbr", dh.month-from-name("MAR"), 3)
#check("month from junk", dh.month-from-name("xyz"), none)
#check("weekday name", dh.weekday-name(6), "Saturday")

All datehog tests passed.

// ── UTC offsets ────────────────────────────────────────────────────────────
#check("offset Z", dh.offset-from-string("Z"), 0)
#check("offset UTC", dh.offset-from-string("UTC"), 0)
#check("offset +02:00", dh.offset-from-string("+02:00"), 120)
#check("offset +0200", dh.offset-from-string("+0200"), 120)
#check("offset -0500", dh.offset-from-string("-0500"), -300)
#check("offset -05", dh.offset-from-string("-05"), -300)
#check("offset +05:30", dh.offset-from-string("+05:30"), 330)
#check("offset UTC+02:00", dh.offset-from-string("UTC+02:00"), 120)
#check("offset passthrough int", dh.offset-from-string(120), 120)
#check("offset junk", dh.offset-from-string("Europe/Berlin"), none)
#check("offset out of range", dh.offset-from-string("+25:00"), none)
#check("offset empty", dh.offset-from-string(""), none)

// With no `--input tz`, local-offset falls back to UTC so documents still
// compile — and compile identically everywhere.
#check("local-offset default", dh.local-offset(), 0)
#check("local-offset custom default", dh.local-offset(default: 60), 60)

// ── range guards (native datetime bounds) ──────────────────────────────────
// Typst's datetime spans years -9999..9999. Overrunning the top is a *compiler
// panic* inside the time crate, not a catchable error, so every entry point
// checks the bound rather than trusting it. These pin that.
#check("min year", dh.MIN-YEAR, -9999)
#check("max year", dh.MAX-YEAR, 9999)
#check("year in range", dh.is-year-in-range(2020), true)
#check("year below range", dh.is-year-in-range(-10000), false)
#check("year above range", dh.is-year-in-range(10000), false)

#check("invalid date -> none", days-from-civil(2020, 2, 30), none)
#check("non-leap 29 Feb -> none", days-from-civil(2019, 2, 29), none)
#check("month 13 -> none", days-from-civil(2020, 13, 1), none)
#check("day 0 -> none", days-from-civil(2020, 1, 0), none)
#check("year 10000 -> none", days-from-civil(10000, 1, 1), none)
#check("negative year works", days-from-civil(-9999, 1, 1), dh.MIN-DAYS)

#check("days above range -> none", civil-from-days(dh.MAX-DAYS + 1), none)
#check("days below range -> none", civil-from-days(dh.MIN-DAYS - 1), none)
#check("max day round-trips", civil-from-days(dh.MAX-DAYS), (9999, 12, 31))
#check("min day round-trips", civil-from-days(dh.MIN-DAYS), (-9999, 1, 1))
#check("weekday out of range -> none", weekday-from-days(dh.MAX-DAYS + 1), none)

// The guard that matters most: a millisecond value past the representable
// range must return none, not panic the compiler.
#check("ms above range -> none", dh.from-ms(dh.MAX-MS + 1), none)
#check("ms below range -> none", dh.from-ms(dh.MIN-MS - 1), none)
#check("max ms is a moment", dh.is-moment(dh.from-ms(dh.MAX-MS)), true)
#check("min ms is a moment", dh.is-moment(dh.from-ms(dh.MIN-MS)), true)
#check("from-parts out of range -> none", dh.from-parts(10000, 1, 1), none)
#check("leap year out of range", dh.is-leap-year(10000), false)

// Far-future/past instants still parse and render.
#check("year 9999 iso", dh.to-iso-date(dh.from-parts(9999, 12, 31)), "9999-12-31")
// Negative years pad to four digits after the sign, as ISO 8601 expanded
// years do: -0044, not -044.
#check("negative year iso", dh.to-iso-date(dh.from-parts(-44, 3, 15)), "-0044-03-15")
