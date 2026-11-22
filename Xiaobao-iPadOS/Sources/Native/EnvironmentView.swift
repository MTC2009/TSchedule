import SwiftUI

struct EnvironmentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                AtmosphereView(inEnvironmentPanel: true).ignoresSafeArea()
                Form {
                    Section {
                        Label(([model.phase.title, weatherTitle] + (model.festival == .none ? [] : [model.festival.title])).joined(separator: " · "), systemImage: model.backgroundSymbol)
                        Toggle("跟随当前时间", isOn: $model.preferences.liveBackground)
                        HStack {
                            Text("背景时刻")
                            Spacer()
                            Text(SchoolClock.time(model.sceneMinute)).monospacedDigit()
                        }
                        Slider(value: $model.preferences.sceneMinute, in: 0...1439, step: 1) { Text("背景时刻") }
                            .disabled(model.preferences.liveBackground)
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 10) {
                                sceneButton(.dawn, "sunrise")
                                sceneButton(.day, "sun.max")
                                sceneButton(.sunset, "sunset")
                                sceneButton(.night, "moon.stars")
                            }
                        }.padding(.vertical, 4)
                    } header: { Text("时间") } footer: { Text("上海时区。单独预览背景不会修改课表。") }
                    Section {
                        Toggle("跟随\(model.cityWeather.city.name)天气", isOn: Binding(
                            get: { model.cityWeather.followsCity }, set: { model.cityWeather.setFollowsCity($0) }
                        )).accessibilityIdentifier("weather-automatic")
                        NavigationLink {
                            WeatherPicker(selection: model.cityWeather.followsCity ? nil : model.preferences.weather,
                                          select: model.previewWeather)
                        } label: {
                            if model.cityWeather.followsCity { Text("手动预览") }
                            else { LabeledContent("手动预览", value: model.preferences.weather.title) }
                        }
                        .accessibilityIdentifier("weather-picker")
                    } header: { Text("天气") } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            weatherStatus.accessibilityIdentifier("weather-status")
                            if model.cityWeather.followsCity {
                                Text("市级模型估算，非气象预警。数据：[Open-Meteo](https://open-meteo.com/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)")
                            }
                        }
                    }
                    if Festival.decorationsEnabled {
                        Section("节日与节气") {
                            Toggle("按真实日期自动识别", isOn: $model.preferences.automaticFestival)
                            Picker("节日与节气", selection: $model.preferences.festival) {
                                Text(Festival.none.title).tag(Festival.none)
                                Section("节日") { ForEach(Festival.holidays) { Text($0.title).tag($0) } }
                                Section("二十四节气") { ForEach(Festival.solarTerms) { Text($0.title).tag($0) } }
                            }.disabled(model.preferences.automaticFestival)
                                .accessibilityIdentifier("sky-season-picker")
                        }
                    }
                    Section("玻璃与外观") {
                        Picker("原生玻璃", selection: $model.preferences.glass) {
                            ForEach(GlassStyle.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("外观", selection: $model.preferences.appearance) {
                            ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("环境动效", isOn: $model.preferences.ambientMotion)
                        if reduceMotion { Text("系统已开启“减少动态效果”。").font(.caption).foregroundStyle(.secondary) }
                    }
                    if Festival.decorationsEnabled {
                        Section { Text("按上海日期显示节日和节气，不改变天气或学校课表。").font(.footnote).foregroundStyle(.secondary) }
                    }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("让环境，透进来。")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var weatherTitle: String {
        switch model.weatherDisplay {
        case .loading: String(localized: "正在更新天气")
        case .unavailable: String(localized: "天气暂无数据")
        case .cached(let sample): String(localized: "\(sample.weather.title)（上次）")
        default: model.weatherDisplay.weather.title
        }
    }

    private var weatherStatus: Text {
        let city = model.cityWeather.city.name
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.locale,
                                      timeZone: SchoolClock.calendar.timeZone)
        switch model.weatherDisplay {
        case .current(let sample):
            return Text("\(city) · \(sample.weather.title) · \(sample.validAt.formatted(format))")
        case .cached(let sample):
            return Text("上次天气：\(city) · \(sample.weather.title) · \(sample.validAt.formatted(format))（缓存）")
        case .loading:
            return Text("正在获取\(city)天气…")
        case .unavailable:
            return Text("暂时无法取得\(city)天气，当前显示默认天空。")
        case .preview:
            return Text("手动预览中，不随城市天气更新。")
        }
    }

    private func sceneButton(_ phase: DayPhase, _ symbol: String) -> some View {
        Button { model.previewScene(model.skyTime.previewMinute(for: phase)) } label: {
            VStack(spacing: 5) { Image(systemName: symbol); Text(phase.title).font(.caption) }.frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.glass)
    }
}

private struct WeatherPicker: View {
    let selection: Weather?
    let select: (Weather) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // A grouped List keeps headings out of the selection and accessibility actions.
        // Picker(.navigationLink) exposes Section headings as selectable-looking rows on iPadOS 26.
        List {
            ForEach(WeatherCategory.allCases) { category in
                Section(category.title) {
                    ForEach(category.conditions) { weather in
                        Button {
                            select(weather)
                            dismiss()
                        } label: {
                            HStack {
                                Label(weather.title, systemImage: weather.symbol)
                                Spacer()
                                if selection == weather {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == weather ? .isSelected : [])
                        .accessibilityIdentifier("weather-\(weather.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("天气")
        .navigationBarTitleDisplayMode(.inline)
    }
}
