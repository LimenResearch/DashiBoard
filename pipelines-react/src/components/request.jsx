import {Button} from "./button";

export function Confirm({children, parameters}) {
    async function getData() {
        const request = new Request("http://127.0.0.1:8080", {
            method: "POST",
            body: JSON.stringify({parameters})
        });
        fetch(request).then(
            x => x.json()
        ).then(
            x => console.log(x)
        );
    }
    return <Button onClick={getData}>
        {children}
    </Button>
}