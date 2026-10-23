// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// Quick answers for the launcher's search field (M0.4): arithmetic,
// percentages and unit conversions. A tokenizer and a recursive-descent
// parser; text is never evaluated as JavaScript.
//
// evaluate(text) returns null, or {kind, value, text}:
//   kind   "math", "percent" or "unit"
//   value  the number
//   text   the answer as shown, e.g. "36" or "3.106855961 mi"
// Only input that contains an operation gets an answer: "42" alone does not.

const units = (function () {
    const table = {};
    // symbol: how the answer shows the unit (default: the first name).
    function add(dimension, factor, names, symbol) {
        for (const name of names) {
            table[name] = {dimension: dimension, factor: factor, key: names[0],
                           symbol: symbol === undefined ? names[0] : symbol};
        }
    }
    add("length", 0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]);
    add("length", 0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres"]);
    add("length", 1, ["m", "meter", "meters", "metre", "metres"]);
    add("length", 1000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"]);
    add("length", 0.0254, ["in", "inch", "inches"]);
    add("length", 0.3048, ["ft", "foot", "feet"]);
    add("length", 0.9144, ["yd", "yard", "yards"]);
    add("length", 1609.344, ["mi", "mile", "miles"]);
    add("length", 1852, ["nmi", "nautical mile", "nautical miles"]);
    add("mass", 1e-6, ["mg", "milligram", "milligrams"]);
    add("mass", 0.001, ["g", "gram", "grams"]);
    add("mass", 1, ["kg", "kilogram", "kilograms", "kilo", "kilos"]);
    add("mass", 1000, ["t", "tonne", "tonnes"]);
    add("mass", 0.028349523125, ["oz", "ounce", "ounces"]);
    add("mass", 0.45359237, ["lb", "lbs", "pound", "pounds"]);
    add("mass", 6.35029318, ["st", "stone", "stones"]);
    add("volume", 0.001, ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]);
    add("volume", 0.01, ["cl", "centiliter", "centiliters", "centilitre", "centilitres"]);
    add("volume", 1, ["l", "liter", "liters", "litre", "litres"], "L");
    add("volume", 1000, ["m3", "cubic meter", "cubic meters", "cubic metre", "cubic metres"], "m³");
    add("volume", 0.00492892159375, ["tsp", "teaspoon", "teaspoons"]);
    add("volume", 0.01478676478125, ["tbsp", "tablespoon", "tablespoons"]);
    add("volume", 0.0295735295625, ["floz", "fl oz", "fluid ounce", "fluid ounces"], "fl oz");
    add("volume", 0.2365882365, ["cup", "cups"]);
    add("volume", 0.473176473, ["pt", "pint", "pints"]);
    add("volume", 0.946352946, ["qt", "quart", "quarts"]);
    add("volume", 3.785411784, ["gal", "gallon", "gallons"]);
    add("speed", 1, ["m/s", "mps"]);
    add("speed", 1 / 3.6, ["km/h", "kmh", "kph"]);
    add("speed", 0.44704, ["mph"]);
    add("speed", 1852 / 3600, ["kn", "knot", "knots"]);
    add("speed", 0.3048, ["ft/s", "fps"]);
    add("data", 1, ["b", "byte", "bytes"], "B");
    add("data", 1e3, ["kb", "kilobyte", "kilobytes"], "kB");
    add("data", 1e6, ["mb", "megabyte", "megabytes"], "MB");
    add("data", 1e9, ["gb", "gigabyte", "gigabytes"], "GB");
    add("data", 1e12, ["tb", "terabyte", "terabytes"], "TB");
    add("data", 1024, ["kib", "kibibyte", "kibibytes"], "KiB");
    add("data", 1048576, ["mib", "mebibyte", "mebibytes"], "MiB");
    add("data", 1073741824, ["gib", "gibibyte", "gibibytes"], "GiB");
    add("data", 1099511627776, ["tib", "tebibyte", "tebibytes"], "TiB");
    add("time", 0.001, ["ms", "millisecond", "milliseconds"]);
    add("time", 1, ["s", "sec", "secs", "second", "seconds"]);
    add("time", 60, ["min", "mins", "minute", "minutes"]);
    add("time", 3600, ["h", "hr", "hrs", "hour", "hours"]);
    add("time", 86400, ["d", "day", "days"]);
    add("time", 604800, ["wk", "week", "weeks"]);
    add("time", 31557600, ["yr", "year", "years"]);
    // Temperatures are not proportional; factor is unused.
    add("temperature", 0, ["°c", "c", "celsius", "degc"], "°C");
    add("temperature", 0, ["°f", "f", "fahrenheit", "degf"], "°F");
    add("temperature", 0, ["k", "kelvin", "kelvins"], "K");
    return table;
})();

function unit(name) {
    return units[String(name).trim().toLowerCase().replace(/\s+/g, " ")] || null;
}

function toKelvin(value, key) {
    if (key === "°c") {
        return value + 273.15;
    }
    if (key === "°f") {
        return (value - 32) * 5 / 9 + 273.15;
    }
    return value;
}

function fromKelvin(value, key) {
    if (key === "°c") {
        return value - 273.15;
    }
    if (key === "°f") {
        return (value - 273.15) * 9 / 5 + 32;
    }
    return value;
}

// At most 10 significant digits, no trailing zeros, no "-0".
function formatNumber(value) {
    if (!isFinite(value)) {
        return null;
    }
    if (value === 0) {
        return "0";
    }
    const magnitude = Math.abs(value);
    if (magnitude >= 1e15 || magnitude < 1e-9) {
        return value.toExponential(6).replace(/\.?0+e/, "e");
    }
    let text = String(Number(value.toPrecision(10)));
    if (text.indexOf("e") >= 0) {
        text = Number(value.toPrecision(10)).toFixed(12).replace(/\.?0+$/, "");
    }
    return text === "-0" ? "0" : text;
}

function tokenize(text) {
    const tokens = [];
    let i = 0;
    while (i < text.length) {
        const ch = text[i];
        if (ch === " " || ch === "\t") {
            i += 1;
        } else if ((ch >= "0" && ch <= "9") || ch === ".") {
            let j = i;
            while (j < text.length && ((text[j] >= "0" && text[j] <= "9") || text[j] === ".")) {
                j += 1;
            }
            const literal = text.slice(i, j);
            if ((literal.match(/\./g) || []).length > 1 || literal === ".") {
                return null;
            }
            tokens.push({type: "number", value: parseFloat(literal)});
            i = j;
        } else if ("+-*/^()%".indexOf(ch) >= 0) {
            tokens.push({type: ch});
            i += 1;
        } else if (ch === "×" || ch === "x" || ch === "X") {
            tokens.push({type: "*"});
            i += 1;
        } else if (ch === "÷") {
            tokens.push({type: "/"});
            i += 1;
        } else {
            return null;
        }
    }
    return tokens;
}

// Grammar:
//   additive       := multiplicative (("+" | "-") (percentage | multiplicative))*
//   multiplicative := power (("*" | "/") power)*
//   power          := unary ("^" power)?
//   unary          := ("-" | "+") unary | postfix
//   postfix        := primary "%"?
//   primary        := number | "(" additive ")"
// "a + b%" and "a - b%" add or take b percent of a.
function Parser(tokens) {
    this.tokens = tokens;
    this.pos = 0;
    this.operations = 0;
}

Parser.prototype.peek = function (type) {
    const token = this.tokens[this.pos];
    return token !== undefined && token.type === type;
};

Parser.prototype.take = function () {
    const token = this.tokens[this.pos];
    this.pos += 1;
    return token;
};

Parser.prototype.isPercentTerm = function () {
    return this.tokens[this.pos] !== undefined && this.tokens[this.pos].type === "number"
        && this.tokens[this.pos + 1] !== undefined && this.tokens[this.pos + 1].type === "%"
        && this.tokens[this.pos + 2] === undefined;
};

Parser.prototype.additive = function () {
    let value = this.multiplicative();
    while (this.peek("+") || this.peek("-")) {
        const op = this.take().type;
        this.operations += 1;
        if (this.isPercentTerm()) {
            const percent = this.take().value;
            this.take();
            value = op === "+" ? value * (1 + percent / 100) : value * (1 - percent / 100);
        } else {
            const right = this.multiplicative();
            value = op === "+" ? value + right : value - right;
        }
    }
    return value;
};

Parser.prototype.multiplicative = function () {
    let value = this.power();
    while (this.peek("*") || this.peek("/")) {
        const op = this.take().type;
        this.operations += 1;
        const right = this.power();
        if (op === "/" && right === 0) {
            throw new Error("division by zero");
        }
        value = op === "*" ? value * right : value / right;
    }
    return value;
};

Parser.prototype.power = function () {
    const base = this.unary();
    if (this.peek("^")) {
        this.take();
        this.operations += 1;
        return Math.pow(base, this.power());
    }
    return base;
};

Parser.prototype.unary = function () {
    if (this.peek("-")) {
        this.take();
        return -this.unary();
    }
    if (this.peek("+")) {
        this.take();
        return this.unary();
    }
    return this.postfix();
};

Parser.prototype.postfix = function () {
    const value = this.primary();
    if (this.peek("%")) {
        this.take();
        this.operations += 1;
        return value / 100;
    }
    return value;
};

Parser.prototype.primary = function () {
    const token = this.take();
    if (token === undefined) {
        throw new Error("unexpected end");
    }
    if (token.type === "number") {
        return token.value;
    }
    if (token.type === "(") {
        const value = this.additive();
        if (!this.peek(")")) {
            throw new Error("missing )");
        }
        this.take();
        return value;
    }
    throw new Error("unexpected token");
};

function calculate(text) {
    const tokens = tokenize(text);
    if (tokens === null || tokens.length === 0) {
        return null;
    }
    const parser = new Parser(tokens);
    try {
        const value = parser.additive();
        if (parser.pos !== tokens.length || parser.operations === 0) {
            return null;
        }
        return isFinite(value) ? value : null;
    } catch (e) {
        return null;
    }
}

function convert(amount, fromName, toName) {
    const from = unit(fromName);
    const to = unit(toName);
    if (from === null || to === null || from.dimension !== to.dimension) {
        return null;
    }
    if (from.dimension === "temperature") {
        return fromKelvin(toKelvin(amount, from.key), to.key);
    }
    return amount * from.factor / to.factor;
}

function evaluate(input) {
    const text = String(input === undefined || input === null ? "" : input).trim();
    if (text.length === 0 || text.length > 200) {
        return null;
    }

    // "15% of 80"
    let match = text.match(/^(.+?)\s*%\s*of\s+(.+)$/i);
    if (match) {
        const percent = calculate("(" + match[1] + ")+0");
        const base = calculate("(" + match[2] + ")+0");
        if (percent === null || base === null) {
            return null;
        }
        const value = percent / 100 * base;
        const shown = formatNumber(value);
        return shown === null ? null : {kind: "percent", value: value, text: shown};
    }

    // "5 km in miles", "100 °F to C"
    match = text.match(/^(-?[\d.]+)\s*([a-zA-Z°/][a-zA-Z°/0-9 ]*?)\s+(?:in|to|as)\s+([a-zA-Z°/][a-zA-Z°/0-9 ]*)$/i);
    if (match) {
        const amount = parseFloat(match[1]);
        const value = isNaN(amount) ? null : convert(amount, match[2], match[3]);
        if (value === null) {
            return null;
        }
        const shown = formatNumber(value);
        if (shown === null) {
            return null;
        }
        const symbol = unit(match[3]).symbol;
        return {kind: "unit", value: value, text: shown + " " + symbol};
    }

    const value = calculate(text);
    if (value === null) {
        return null;
    }
    const shown = formatNumber(value);
    return shown === null ? null : {kind: "math", value: value, text: shown};
}
