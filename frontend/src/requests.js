import { host, port } from "./request.json"

export function loadJSON(input, def) {
    return input.files[0]
        .text()
        .then(JSON.parse)
        .catch(_ => {
            console.log("Could not load file.");
            return def;
        });
}

export function downloadJSON(obj, ref) {
    const data = JSON.stringify(obj)
    const blob = new Blob([data], {type: "application/json"});
    const href = window.URL.createObjectURL(blob);
    ref.href = href;
    ref.click();
    ref.href = "";
    window.URL.revokeObjectURL(href);
}

export function getURL(page) {
    return "http://" + host + ":" + port + "/" + page;
}

export function postRequest(page, body, def) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch(
        getURL(page),
        {
            method: "POST",
            body: JSON.stringify(body),
            headers: myHeaders,
        });

    return response
        .then(x => x.json())
        .catch(
            _ => {
                console.log("Request to " + page + " failed");
                return def;
            }
        );
}
