import { host, port } from "./request.json"

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
