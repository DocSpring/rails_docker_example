# Fast Docker builds for Rails and Webpack

> These scripts have been tested with Docker version `18.06.0-ce`, build `0ffa825`.

### Overview

* Use Docker's cached layers for gems, npm packages, and assets, if the relevant files have not been modified (`Gemfile`, `Gemfile.lock`, `package.json`, etc.)
* Use a [multi-stage build](https://docs.docker.com/develop/develop-images/multistage-build/) so
that Rails assets and the webpack build are cached independently.
* Use the webpack [DllPlugin](https://webpack.js.org/plugins/dll-plugin/) to split the main dependencies into a separate file. This means that we only need to compile the main libraries once (e.g. React, Redux)
  * I used a separate `package.json` to take advantage of Docker's caching.
* If there are any changes to `Gemfile` or `package.json`, re-use the gems and packages from the first build. (Don't download everything from scratch.)
* If there are any changes to assets, re-use the assets and cache from the previous build.
* Only include necessary files in the final image.
  * A production Rails app doesn't need any files in `app/assets`, `node_modules`, or front-end source code. A lot of gems also have some junk files that can be safely removed (e.g. `spec/`, `test/`, `README.md`)
* Include the [bootsnap](https://github.com/Shopify/bootsnap) cache in the final image,
  to speed up server boot and rake tasks.
* After building a new image, create a small "diff layer" between the new image and the previous image. This layer only includes the changed files.
* Create a nested sequence of diff layers, but reset the sequence if there are too many layers (> 30), or if the diff layers add up to more than 80% of the base layer's size.
* Use Nginx for better concurrency and to serve static assets

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

### Walkthrough

Make a change in `react-webpack-rails-tutorial/app/views/layouts/application.html.erb`:

```bash
echo "hello world" >> react-webpack-rails-tutorial/app/views/layouts/application.html.erb
```

Now run `./scripts/build_app`

When you run `docker history demoapp/app:latest`, you should see a small rsync layer at the top, which only includes the changed file:

```
IMAGE               CREATED             CREATED BY                                      SIZE                COMMENT
fcb9dfcf1fcf        14 seconds ago      rsync --recursive --links --progress --check…   809B
e3cdd669d928        2 hours ago                                                         2.1MB               merge sha256:68ac83c9746edb79dd90791ac6c07016a1d065dfb3ea4f49cc81faa2073cb510 to sha256:402c0958413f4c061c293413010ab300b3735aae518f8b48a85aeafa78fe94dd
<missing>           2 hours ago         /bin/sh -c #(nop)  CMD ["foreman" "start"]      0B
<missing>           2 hours ago         /bin/sh -c #(nop)  EXPOSE 80                    0B
```

> Note: The second build uses an updated base image, so the Docker layers are not fully cached. `bundle install` and `yarn install` should still be very fast, since they don't have to download anything. All the builds after this one will use cached layers, so they'll be even faster (if you don't change any gems or npm packages.)

Now remove the `awesome_print` gem from the `Gemfile` and update `Gemfile.lock`:

```bash
cd react-webpack-rails-tutorial
cat Gemfile | grep -v "awesome_print" > Gemfile.new && mv Gemfile.new Gemfile
bundle install
cd ..
```

Run `./scripts/build_app`

Notice that while the `bundle install` is not fully cached, it is still using all of the gems from the previous build.

Now change a Rails asset:

```bash
echo "body { color: blue; }" >> react-webpack-rails-tutorial/app/assets/stylesheets/test-asset.css
```

Run `./scripts/build_app`

You'll see that the webpack steps are fully cached, but the `assets:precompile` task is run.

Now change a webpack asset in `client`:

```bash
echo "body { color: green; }" >> react-webpack-rails-tutorial/client/app/assets/styles/app-variables.scss
```

Run `./scripts/build_app`

You'll see that the `assets:precompile` task is fully cached, but the webpack build is run.

## Image Tags

The `build_app` script uses the following tags to implement caching and diff layers:

#####  `demoapp/ruby-node:latest`

Contains specific versions of Ruby, Node.js, and Yarn.

(I started by using some [`ruby-node`](https://hub.docker.com/r/starefossen/ruby-node/)
images from Docker Hub, but I prefer to have full control over the versions.)

##### `demoapp/base:latest`

Based on `demoapp/ruby-node`. Installs Linux packages, such as `build-essential`, `postgresql-client`, `nginx`, and `rsync`. It also sets up some directories and environment variables.

##### `demoapp/app:base-webpack-build`

The base image for the webpack build. The initial build uses `demoapp/base` as the base image, and then tags the resulting image with `demoapp/app:base-webpack-build`. All the subsequent builds use this first build as the base image. We only set the `base-webpack-build` once and don't update it very often, because if it keeps changing then Docker can't cache any layers.

##### `demoapp/app:base-assets-build`

The base image for the assets build.


##### `demoapp/app:latest-assets-build`

The most recent assets build. We copy in the assets and Sprockets cache from this build before running `rake assets:precompile`. This way, we can take advantage of Docker's layer caching while also using the latest assets cache.

##### `demoapp/app:current-webpack-build`, `demoapp/app:current-assets-build`

 The build that is currently in progress. We need this tag because we run `docker build` multiple times, targeting different stages in `Dockerfile.app`. After compiling webpack, we save everything as the `latest-webpack-build` tag. And after compiling assets, we save everything as the `latest-assets-build` tag. This includes all of the cached files that we want to re-use in the next build. However, we don't need any of these files in production, so the final build runs some commands to clean up the image and remove unnecessary files, then squashes everything into a single layer.

##### `demoapp/app:current`

The in-progress production build that contains the final squashed layer. We don't override the `demoapp/app:latest` tag immediately, because the last step is to produce a small diff layer between `demoapp/app:latest` and `demoapp/app:current`

##### `demoapp/app:latest`

This is the final production image after running `./scripts/build_app`.

## Notes About Webpack DLL Plugin

I added webpack's `DllPlugin` and `DllReferencePlugin` as a proof-of-concept for vendored libraries. The main idea is that if you use a separate `package.json` and `webpack.config.js`, Docker will cache these layers when the files haven't changed, so you cache the vendored packages and libraries. You just have to remember to run `yarn add <package>` in `client/vendor`, instead of `client`. If you add a package to `client/package.json` instead of `client/vendor/package.json`, it will work fine, but the package won't be included in your vendored DLL.

This works great as a demo, and the `DllPlugin` can definitely be used in production, but this implementation isn't very clean and there are a lot of things that can be improved.

`react-webpack-rails-tutorial` was already using the `CommonsChunkPlugin` to create their own vendored libaries. This runs during the main webpack build, so it can't be cached independently.


## More info about the react-webpack-rails-tutorial app

* Demo app: [react-webpack-rails-tutorial](https://github.com/shakacode/react-webpack-rails-tutorial)
* [Setup instructions for demo app](https://github.com/shakacode/react-webpack-rails-tutorial#basic-demo-setup)
