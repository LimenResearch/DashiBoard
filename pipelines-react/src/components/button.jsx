export function Button({positive=true, children, ...props}) {
    const btnClass = `text-xl font-semibold rounded text-left py-2 px-4 mr-4
                      bg-opacity-75 border-2 border-transparent`;
    const posClass = `bg-blue-100 hover:bg-blue-200 text-blue-800
                      hover:text-blue-900 focus:border-blue-500`;
    const negClass = `bg-red-100 hover:bg-red-200 text-red-800
                      hover:text-red-900 focus:border-red-500`;
    const className = btnClass + ' ' + (positive ? posClass : negClass);

    return <button {...props} className={className}>{children}</button>;
}
