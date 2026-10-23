// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import StarOS.Shell

// QuickAnswers (quickanswers.js): arithmetic, percentages and unit
// conversions, and the inputs that must not get an answer.
TestCase {
    name: "QuickAnswers"

    function test_answers_data() {
        return [
            {tag: "multiply", input: "12*3", text: "36", kind: "math"},
            {tag: "add", input: "2+2", text: "4", kind: "math"},
            {tag: "parentheses", input: "(1+2)*3", text: "9", kind: "math"},
            {tag: "power", input: "2^10", text: "1024", kind: "math"},
            {tag: "divide", input: "10/4", text: "2.5", kind: "math"},
            {tag: "float noise", input: "0.1+0.2", text: "0.3", kind: "math"},
            {tag: "ten digits", input: "1/3", text: "0.3333333333", kind: "math"},
            {tag: "negative", input: "-5+2", text: "-3", kind: "math"},
            {tag: "x as times", input: "2x3", text: "6", kind: "math"},
            {tag: "times sign", input: "7 × 6", text: "42", kind: "math"},
            {tag: "division sign", input: "9 ÷ 3", text: "3", kind: "math"},
            {tag: "square root", input: "2^0.5", text: "1.414213562", kind: "math"},
            {tag: "huge", input: "2^1000", text: "1.071509e+301", kind: "math"},
            {tag: "percent of", input: "15% of 80", text: "12", kind: "percent"},
            {tag: "plus percent", input: "80 + 15%", text: "92", kind: "math"},
            {tag: "minus percent", input: "80 - 25%", text: "60", kind: "math"},
            {tag: "percent alone", input: "50%", text: "0.5", kind: "math"},
            {tag: "km to miles", input: "5 km in miles", text: "3.106855961 mi", kind: "unit"},
            {tag: "celsius to fahrenheit", input: "100 c to f", text: "212 °F", kind: "unit"},
            {tag: "fahrenheit to celsius", input: "32 °F in C", text: "0 °C", kind: "unit"},
            {tag: "celsius to kelvin", input: "0 c in k", text: "273.15 K", kind: "unit"},
            {tag: "binary to decimal data", input: "1 gib in mb", text: "1073.741824 MB", kind: "unit"},
            {tag: "speed", input: "60 mph in km/h", text: "96.56064 km/h", kind: "unit"},
            {tag: "two-word unit", input: "1 nautical mile in km", text: "1.852 km", kind: "unit"},
            {tag: "volume", input: "1 gallon in liters", text: "3.785411784 L", kind: "unit"},
            {tag: "inches named in", input: "5 in in cm", text: "12.7 cm", kind: "unit"},
            {tag: "time", input: "90 min to hours", text: "1.5 h", kind: "unit"}
        ];
    }

    function test_answers(data) {
        const result = QuickAnswers.evaluate(data.input);
        verify(result !== null, data.input + " has an answer");
        compare(result.text, data.text);
        compare(result.kind, data.kind);
    }

    function test_no_answer_data() {
        return [
            {tag: "plain number", input: "42"},
            {tag: "exponent notation", input: "1e3"},
            {tag: "negative number", input: "-5"},
            {tag: "empty", input: ""},
            {tag: "app name", input: "firefox"},
            {tag: "app name with digits", input: "kcalc"},
            {tag: "division by zero", input: "10/0"},
            {tag: "different dimensions", input: "5 km in kg"},
            {tag: "unknown unit", input: "5 parsecs in km"},
            {tag: "unbalanced", input: "(1+2"},
            {tag: "two points", input: "1..2+1"},
            {tag: "dangling operator", input: "2 +"},
            {tag: "note", input: "note: hi"},
            {tag: "code", input: "alert(1)+1"},
            {tag: "null", input: null},
            {tag: "too long", input: "1+".repeat(150) + "1"}
        ];
    }

    function test_no_answer(data) {
        compare(QuickAnswers.evaluate(data.input), null);
    }
}
