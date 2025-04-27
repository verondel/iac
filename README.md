1. create key.json
2. create ./secrets/yc-token.txt (`yc config get token`)
3. `make cloud`
4. `make services`
5. get gitlab login: "root", password: `kubectl get secret -n gitlab gitlab-gitlab-initial-root-password -o jsonpath="{.data.password}" | base64 --decode` 
6. change root password! (not use `<ur_name>_<birth_year>`, be smarter as a creator of this repo by using `<birth_year>_<ur_name>`)
7. `Admin Area > Settings > General > Sign-up restrictions`
