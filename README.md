# Fast Docker builds for Rails and Webpack

> These scripts have been tested with Docker version `18.06.0-ce`, build `0ffa825`.

### Overview

* Uses Docker's cached layers for gems, npm packages, and assets, if the relevant files have not been changed (`Gemfile`, `Gemfile.lock`, `package.json`, etc.)
* Uses a [multi-stage build](https://docs.docker.com/develop/develop-images/multistage-build/) so
that Rails assets and the webpack build are cached independently.
* If there are any changes to `Gemfile` or `package.json`, re-uses the gems and packages from the first build.
  * I experimented with copying in the gems and packages from the *latest* build, but the `COPY` command took much longer than installing a few gems or packages. The
  new layer will also be cached if you don't make any further changes to the relevant files.
* If there are any changes to assets, re-uses the assets cache from the previous build.
* Only includes necessary files in the final image.
  * A production Rails app doesn't use any files in `app/assets`, `node_modules`, or front-end source code. A lot of gems also have some junk files that are removed (e.g. `spec/`, `test/`, `README.md`)
* Include [bootsnap](https://github.com/Shopify/bootsnap) cache in the final image,
  so that the server and rake tasks start a lot faster.
* After building a new image, creates a small "diff layer" between the new image and the previous image. This layer only includes the changed files.
* Creates a sequence of diff layers, and resets the base image if there are too many layers (> 30), or if the diff layers add up to more than 80% of the base layer's size.
* Uses Nginx for better concurrency, and to serve static assets

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

Now change a Rails asset:

```bash
echo "body { color: blue; }" >> react-webpack-rails-tutorial/app/assets/stylesheets/test-asset.css
```

Then run `./scripts/build_app`. You'll see that the webpack steps are fully cached, but the `assets:precompile` task is run.

Now change a webpack asset in `client`:

```bash
echo "body { color: green; }" >> react-webpack-rails-tutorial/client/app/assets/styles/app-variables.scss
```

Then run `./scripts/build_app`. You'll see that the `assets:precompile` task is fully cached, but the webpack build is run.

We're using a multi-stage build, and the assets and webpack stages both inherit from the `npm_rake` stage. This means that they can be cached independently and don't depend on each other.


# Image Tags

The build script uses the following tags to implement caching and diff layers:

###  `demoapp/ruby-node:latest`

Contains specific versions of Ruby, Node.js, and Yarn.
I started by using some `ruby-node` images from Docker Hub,
but I've found that it's much better to have full control over these versions.

### `demoapp/base:latest`

Based on `demoapp/ruby-node`. Contains Linux packages (e.g. `build-essential`, `postgresql-client`, `nginx`, `rsync`), and also sets up some directories and environment variables.

### `demoapp/app:base-build`

 The base image for the app build. The initial build uses `demoapp/base` as the base image, and then tags the resulting image with `demoapp/app:base-build`. All the subsequent builds use this initial build as the base image. We only set the `base-build` once, because if it keeps changing then Docker can't do any caching.

### `demoapp/app:latest-build`

 The most recent build. We copy in the assets and Sprockets cache from this build before running `rake assets:precompile`. This way, we can take advantage of Docker's layer caching while also using the latest assets cache.

### `demoapp/app:current-build`

 The build that is currently in progress. We need this tag because we run `docker build` twice, targeting two different stages in `Dockerfile.app`. After compiling assets, we save the whole build image as the `latest-build` tag. This includes all of the cache files that we want to re-use in the next build, but we don't need any of these files in production. So the second build re-uses all of these layers, but then runs some commands to clean up the image and remove unnecessary files, then finally squashes everything into a single layer.

### `demoapp/app:current`

This the in-progress production build that contains the final squashed layer. We don't override the `demoapp/app:latest` tag immediately, because we want to produce a small diff layer between `demoapp/app:latest` and `demoapp/app:current`

### `demoapp/app:latest`

After running `./scripts/build_app`, this is the final production image.


## More info about the react-webpack-rails-tutorial app

* Demo app: [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial)
* [Setup instructions for demo app](https://github.com/shakacode/react-webpack-rails-tutorial#basic-demo-setup)
