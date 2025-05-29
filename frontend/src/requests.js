import { host, port } from "./request.json"

export function downloadJSON(filename, data) {
    const blob = new Blob([data], {type: "application/json"});
    const href = window.URL.createObjectURL(blob);
    const elem = window.document.createElement('a');
    elem.download = filename;
    elem.href = href;
    elem.style.display = "none";
    document.body.appendChild(elem);
    elem.click();
    document.body.removeChild(elem);
    window.URL.revokeObjectURL(href);
}

export function getURL(page) {
    return "http://" + host + ":" + port + "/" + page;
}

export function postRequest(page, body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch(
        getURL(page),
        {
            method: "POST",
            body: JSON.stringify(body),
            headers: myHeaders,
        });

    return response;
}
