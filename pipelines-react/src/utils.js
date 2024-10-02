function nonEmpty(s) {
    return s.length > 0;
}

export function parseValue(value) {
    return value.split(' ').filter(nonEmpty);
}

export function nextIndex(value, len) {
    return (value < 0 || value >= len - 1) ? 0 : value + 1;
}

export function prevIndex(value, len) {
    return (value < 1 || value >= len) ? len - 1 : value - 1;
}

function isMatch(value) {
    const str = value.toLowerCase();
    return text => text.toLowerCase().startsWith(str);
}

export function getEntries(value, options) {
    const idx = value.lastIndexOf(' ');
    const slice = value.slice(idx + 1, value.length);
    const keys = options.filter(isMatch(slice));
    return keys.map(key => {
        const completion = value.slice(0, idx + 1) + key + ' ';
        return {key, value: completion};
    });
}
