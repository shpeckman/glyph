# Makefile
.PHONY: all fonts run-examples clean

all: spec

spec:
	crystal spec

fonts:
	mkdir -p examples/fonts
	curl -L -o examples/fonts/Inter-Variable.ttf "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-VariableFont_slnt,wght.ttf"
	curl -L -o examples/fonts/SourceCodePro-Regular.otf "https://github.com/adobe-fonts/source-code-pro/raw/release/OTF/SourceCodePro-Regular.otf"
	curl -L -o examples/fonts/Nabla-Regular.ttf "https://github.com/googlefonts/nabla/raw/main/fonts/ttf/Nabla-Regular.ttf"
	curl -L -o examples/fonts/MaterialSymbols.ttf "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsOutlined%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"

examples: fonts
	@echo "--- Running basic_raster.cr ---"
	crystal run examples/basic_raster.cr
	@echo "\n--- Running subpixel_lcd.cr ---"
	crystal run examples/subpixel_lcd.cr
	@echo "\n--- Running variable_axes.cr ---"
	crystal run examples/variable_axes.cr
	@echo "\n--- Running color_compositor.cr ---"
	crystal run examples/color_compositor.cr

clean:
	rm -rf examples/fonts
	rm -f examples/color_output.ppm