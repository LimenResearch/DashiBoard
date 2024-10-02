import {useRouteError} from "react-router-dom";

export function ErrorPage() {
    const error = useRouteError();
    console.error(error);

    return (
        <div id="error-page" className="bg-gray-100 min-h-screen p-8">
            <h1 className="text-2xl font-bold text-gray-900">Oops!</h1>
            <p>Sorry, an unexpected error has occurred.</p>
            <p>
                <i>{error.statusText || error.message}</i>
            </p>
        </div>

    );
}