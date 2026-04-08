export const getCsrftoken = (): Promise<string | null> => {
    return new Promise((resolve, reject) => {
        fetch("/api-auth/login/", {
            method: "GET",
        }).then(async (response) => {
            if (!response.ok) {
                reject(null);
            }

            const html = await response.text();
            //   <input type="hidden" name="csrfmiddlewaretoken" value="lVJhBE20Q2SylDkpBHtqYn0FFrYcGf3ko4u8vOnZPzW8EIMmWr20Yb4JhRSiJ7ak">
            const match = html.match(/name=["|']csrfmiddlewaretoken["|'] value=["|'](.+?)["|']/);
            const token = match ? match[1] : null;
            // console.log(`html: ${html}`);
            console.debug(`token: ${token}`);
            if (token) {
                resolve(token);
            } else {
                reject(null);
            }
        });
    });
};