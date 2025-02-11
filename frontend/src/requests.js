import { host, port } from "./request.json"

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
