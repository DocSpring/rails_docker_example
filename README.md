# Fast Docker builds for Rails and Webpack

> These scripts have been tested with Docker version `18.06.0-ce`, build `0ffa825`.

Features:

* Use Docker's layer cache for gems, npm packages, and assets, if the relevant files have not been changed
* If there are any changes to `Gemfile` or `package.json`, re-use the gems and packages from the previous build
* If there are any changes to assets, re-use the assets cache from the previous build
* Only include the necessary files in the final image
  * Production doesn't need any files in `app/assets`, npm packages, or front-end source code
* After building a new image, create a "diff layer" between the new image and the previous image,
  so that it only includes the changed files
* Create a sequence of diff layers, and enforce a maximum number of layers so that the image doesn't grow too large
* Use Nginx to serve static assets and for better concurrency


## Build Docker images and start the Rails app

```bash
# Clone rails_docker_example repo + submodules
git clone --recursive https://github.com/FormAPI/rails_docker_example.git
cd rails_docker_example
./scripts/build_ruby_node
./scripts/build_base
./scripts/build_app
docker-compose up --no-start
docker-compose run --rm web rake db:create db:migrate
docker-compose up
```

Then visit [localhost:3000](http://localhost:3000).
The app should be running and you should be able to add a comment. (If you open the app in
two different tabs, the comments should update in real-time via websockets.)

Make a change in `react-webpack-rails-tutorial/app/views/layouts/application.html.erb`, then
run `./scripts/build_app`.

When you run `docker history demoapp/app:latest`, you should see a small rsync layer at the top:

```
IMAGE               CREATED             CREATED BY                                      SIZE                COMMENT
fcb9dfcf1fcf        14 seconds ago      rsync --recursive --links --progress --check…   809B
e3cdd669d928        2 hours ago                                                         2.1MB               merge sha256:68ac83c9746edb79dd90791ac6c07016a1d065dfb3ea4f49cc81faa2073cb510 to sha256:402c0958413f4c061c293413010ab300b3735aae518f8b48a85aeafa78fe94dd
<missing>           2 hours ago         /bin/sh -c #(nop)  CMD ["foreman" "start"]      0B
<missing>           2 hours ago         /bin/sh -c #(nop)  EXPOSE 80                    0B
```

Now remove the `awesome_print` gem from the `Gemfile` and update `Gemfile.lock`:

```bash
cd react-webpack-rails-tutorial
cat Gemfile | grep -v "awesome_print" > Gemfile.new && mv Gemfile.new Gemfile
bundle install
cd ..
```

Then run `./scripts/build_app`.

Notice that while the `bundle install` and `yarn install` are not fully cached, they are still using all of the gems and npm packages from the previous build.


## More info about the react-webpack-rails-tutorial app

* Demo app: [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial)
* [Setup instructions for demo app](https://github.com/shakacode/react-webpack-rails-tutorial#basic-demo-setup)
