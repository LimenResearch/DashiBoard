import { host, port } from "./request.json"

export function postRequest(page, body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch("http://" + host + ":" + port + "/" + page, {
        method: "POST",
        body: JSON.stringify(body),
        headers: myHeaders,
    });

    return response;
}
