export const sessionName = "user-experiment";

export function postRequest(page, body) {
    const myHeaders = new Headers();
    myHeaders.append("Content-Type", "application/json");

    const response = fetch("http://127.0.0.1:8080/" + page, {
        method: "POST",
        body: JSON.stringify(body),
        headers: myHeaders,
    });

    return response;
}
